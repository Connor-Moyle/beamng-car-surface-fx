-- Car Surface FX: where the mud (and the rubber) thrown off a tyre lands on the car. Baked once per car model from the car's own paint triangles (the same `tris` and `wheels`
-- carSurfaceFx/bodymap.build takes: tris = { pos = {9 numbers}, uv = {6 numbers} } in the car's frame, x left, y back, z up; wheels = { x, y, z, r [, w] } at rest):
-- for each wheel rays leave the tread, the way the tyre throws them, with the pull of the air and gravity, and the first triangle each one hits gives a point on the paint texture.
--   * the tread turns so that its top moves forward; a lump leaves tangentially: off the top it goes forward, off the back of the tyre straight up, off the underside backward
--     and up. phi runs from the top (0) over the rear (90 degrees) to the underside (180 degrees); the front half of the tyre throws nothing at the body.
--   * the speed of the throw is the car's (the tyre's rim speed) plus what wheelspin adds; the air pulls the lump back toward the ground's rest frame (backward in the car's
--     frame) and gravity down: a path that bends back with speed. The cone widens with speed and slip.
--   * nothing is carried further than `reach` (2.5 m of path), and a hit near the wheel weighs more than a far one.
-- bake(tris, wheels, opts) returns { wheels = { [i] = { hits = { { u, v, weight, dx, dy, s, dist } ... }, rays, count } }, reach }. The spatial grid keeps it O(rays x a few
-- triangles); bake is a plain function, and `opts.yield` (a function called every few rays) lets the caller spread it over frames (a coroutine yield). Pure, tested outside the game.
local M = {}

local sqrt, floor, exp, sin, cos, max, min, abs, pi = math.sqrt, math.floor, math.exp, math.sin, math.cos, math.max, math.min, math.abs, math.pi

M.DEFAULTS = {
  rays = 500,            -- per wheel
  reach = 2.5,           -- m of path
  cell = 0.2,            -- m, the grid
  width = 0.22,          -- m, the tyre's width when the wheel has none
  speed = 20,            -- m/s, the car's speed the throw is worked out for
  slip = 0,              -- 0..1, wheelspin: more speed of throw, a wider cone
  seed = 7,
  yieldEvery = 25,
}

-- ---- the spatial grid of triangles ---------------------------------------------------------------------------------------------------------------------------

local function gradients(t)
  local p, uv = t.pos, t.uv
  local e1x, e1y, e1z, e2x, e2y, e2z = p[4] - p[1], p[5] - p[2], p[6] - p[3], p[7] - p[1], p[8] - p[2], p[9] - p[3]
  local g11, g12, g22 = e1x * e1x + e1y * e1y + e1z * e1z, e1x * e2x + e1y * e2y + e1z * e2z, e2x * e2x + e2y * e2y + e2z * e2z
  local det = g11 * g22 - g12 * g12
  if abs(det) < 1e-14 then return nil end
  local Ax, Ay, Az = (g22 * e1x - g12 * e2x) / det, (g22 * e1y - g12 * e2y) / det, (g22 * e1z - g12 * e2z) / det
  local Bx, By, Bz = (g11 * e2x - g12 * e1x) / det, (g11 * e2y - g12 * e1y) / det, (g11 * e2z - g12 * e1z) / det
  local du1, dv1, du2, dv2 = uv[3] - uv[1], uv[4] - uv[2], uv[5] - uv[1], uv[6] - uv[2]
  return Ax * du1 + Bx * du2, Ay * du1 + By * du2, Az * du1 + Bz * du2, Ax * dv1 + Bx * dv2, Ay * dv1 + By * dv2, Az * dv1 + Bz * dv2
end

-- grid = { cell, x0, y0, z0, nx, ny, nz, cells = { [key] = { tri index ... } }, t = { flat triangle data }, tris }
function M.grid(tris, cell)
  local x0, y0, z0, x1, y1, z1 = 1e9, 1e9, 1e9, -1e9, -1e9, -1e9
  for _, t in ipairs(tris) do
    for c = 0, 2 do
      local x, y, z = t.pos[c * 3 + 1], t.pos[c * 3 + 2], t.pos[c * 3 + 3]
      x0, y0, z0, x1, y1, z1 = min(x0, x), min(y0, y), min(z0, z), max(x1, x), max(y1, y), max(z1, z)
    end
  end
  if x0 > x1 then return nil end
  local g = { cell = cell, x0 = x0 - 0.01, y0 = y0 - 0.01, z0 = z0 - 0.01, cells = {}, tris = tris, tri = {}, stamp = {} }
  g.nx, g.ny, g.nz = floor((x1 - g.x0) / cell) + 1, floor((y1 - g.y0) / cell) + 1, floor((z1 - g.z0) / cell) + 1
  local cells, nx, ny = g.cells, g.nx, g.ny
  for i, t in ipairs(tris) do
    local p = t.pos
    local ax, ay, az = min(p[1], p[4], p[7]), min(p[2], p[5], p[8]), min(p[3], p[6], p[9])
    local bx, by, bz = max(p[1], p[4], p[7]), max(p[2], p[5], p[8]), max(p[3], p[6], p[9])
    g.tri[i] = { p[1], p[2], p[3], p[4] - p[1], p[5] - p[2], p[6] - p[3], p[7] - p[1], p[8] - p[2], p[9] - p[3] }
    g.stamp[i] = 0
    for iz = floor((az - g.z0) / cell), floor((bz - g.z0) / cell) do
      for iy = floor((ay - g.y0) / cell), floor((by - g.y0) / cell) do
        for ix = floor((ax - g.x0) / cell), floor((bx - g.x0) / cell) do
          local k = ix + iy * nx + iz * nx * ny
          local list = cells[k]
          if not list then list = {} cells[k] = list end
          list[#list + 1] = i
        end
      end
    end
  end
  g.mark = 0
  return g
end

-- the first triangle the segment o -> o + s hits (Moller-Trumbore, two-sided): t in 0..1, the index and the barycentric a, b; nil when none.
function M.segment(g, ox, oy, oz, sx, sy, sz)
  local cell, nx, ny = g.cell, g.nx, g.ny
  local ex, ey, ez = ox + sx, oy + sy, oz + sz
  local ix0, ix1 = floor((min(ox, ex) - g.x0) / cell), floor((max(ox, ex) - g.x0) / cell)
  local iy0, iy1 = floor((min(oy, ey) - g.y0) / cell), floor((max(oy, ey) - g.y0) / cell)
  local iz0, iz1 = floor((min(oz, ez) - g.z0) / cell), floor((max(oz, ez) - g.z0) / cell)
  g.mark = g.mark + 1
  local mark, stamp, tri = g.mark, g.stamp, g.tri
  local bestT, bestI, bestA, bestB = 1.0000001, nil, nil, nil
  for iz = max(0, iz0), min(g.nz - 1, iz1) do
    for iy = max(0, iy0), min(ny - 1, iy1) do
      for ix = max(0, ix0), min(nx - 1, ix1) do
        local list = g.cells[ix + iy * nx + iz * nx * ny]
        if list then
          for n = 1, #list do
            local i = list[n]
            if stamp[i] ~= mark then
              stamp[i] = mark
              local d = tri[i]
              local e1x, e1y, e1z, e2x, e2y, e2z = d[4], d[5], d[6], d[7], d[8], d[9]
              -- p = s x e2
              local px, py, pz = sy * e2z - sz * e2y, sz * e2x - sx * e2z, sx * e2y - sy * e2x
              local det = e1x * px + e1y * py + e1z * pz
              if det > 1e-12 or det < -1e-12 then
                local inv = 1 / det
                local tx, ty, tz = ox - d[1], oy - d[2], oz - d[3]
                local a = (tx * px + ty * py + tz * pz) * inv
                if a >= 0 and a <= 1 then
                  local qx, qy, qz = ty * e1z - tz * e1y, tz * e1x - tx * e1z, tx * e1y - ty * e1x
                  local b = (sx * qx + sy * qy + sz * qz) * inv
                  if b >= 0 and a + b <= 1 then
                    local t = (e2x * qx + e2y * qy + e2z * qz) * inv
                    if t >= 0 and t < bestT then bestT, bestI, bestA, bestB = t, i, a, b end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  if bestI then return bestT, bestI, bestA, bestB end
end

-- the first hit along a path (a list of points, the path is the polyline); returns the triangle index, a, b, the path length to the hit and the direction of the segment there
function M.trace(g, pts)
  local len = 0
  for k = 1, #pts - 1 do
    local a, b = pts[k], pts[k + 1]
    local sx, sy, sz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local t, i, ba, bb = M.segment(g, a[1], a[2], a[3], sx, sy, sz)
    local sl = sqrt(sx * sx + sy * sy + sz * sz)
    if t then return i, ba, bb, len + t * sl, sx / sl, sy / sl, sz / sl end
    len = len + sl
  end
end

-- ---- the throw -----------------------------------------------------------------------------------------------------------------------------------------------

-- one lump leaving the tread at phi (0 top, 90 degrees rear, 180 underside) and `lat` (-1..1 across the tread): its path as points in the car's frame
function M.path(wheel, phi, lat, spread, p, rnd)
  local w = wheel.w or p.width
  local cs, sn = cos(phi), sin(phi)
  local ox, oy, oz = wheel.x + lat * w * 0.5, wheel.y + wheel.r * sn, wheel.z + wheel.r * cs
  local vt = p.speed * (1 + 2 * p.slip) + 1.5                              -- m/s: the rim speed, more with wheelspin, a little even when slow
  local vy, vz = -cs * vt, sn * vt                                         -- tangent: the top forward (-y), the rear up, the underside backward
  local vx = (rnd() - 0.5) * 2 * spread * vt                               -- the cone
  vy, vz = vy + (rnd() - 0.5) * 0.4 * spread * vt, vz + (rnd() - 0.5) * 0.4 * spread * vt
  local pts = { { ox, oy, oz } }
  local x, y, z, len = ox, oy, oz, 0
  local tau, dt = 0.18, 0.01
  local airY = p.speed                                                     -- the air at rest in the world is moving backward (+y) in the car's frame
  for _ = 1, 80 do
    vy = vy + ((airY - vy) / tau) * dt
    vx = vx - (vx / tau) * dt
    vz = vz - (vz / tau) * dt - 9.81 * dt
    local nx_, ny_, nz_ = x + vx * dt, y + vy * dt, z + vz * dt
    len = len + sqrt((nx_ - x) ^ 2 + (ny_ - y) ^ 2 + (nz_ - z) ^ 2)
    x, y, z = nx_, ny_, nz_
    if _ % 2 == 0 then pts[#pts + 1] = { x, y, z } end
    if len > p.reach then break end
  end
  return pts
end

local function rngFor(seed)
  local s = floor(seed) % 2147483646 + 1
  return function() s = (s * 16807) % 2147483647 return s / 2147483647 end
end

-- the hits of one wheel
local function bakeWheel(g, wheel, p, yield)
  local rnd = rngFor(p.seed + floor(wheel.x * 100) * 7 + floor(wheel.y * 100) * 13)
  local hits, n = {}, 0
  local spread = 0.08 + 0.22 * min(1, p.speed / 30) + 0.1 * p.slip
  local reach = p.reach
  for k = 1, p.rays do
    -- stratified over the rear half of the tyre, a little more off the top and rear than the underside
    local phi = ((k - 1 + rnd()) / p.rays) * pi
    local lat = rnd() * 2 - 1
    local pts = M.path(wheel, phi, lat, spread, p, rnd)
    local i, a, b, dist, dx, dy, dz = M.trace(g, pts)
    if i and dist > 0.02 and dist <= reach then
      local t = g.tris[i]
      local uv = t.uv
      local u = uv[1] + a * (uv[3] - uv[1]) + b * (uv[5] - uv[1])
      local v = uv[2] + a * (uv[4] - uv[2]) + b * (uv[6] - uv[2])
      local jux, juy, juz, jvx, jvy, jvz = gradients(t)
      if jux then
        local du, dv = dx * jux + dy * juy + dz * juz, dx * jvx + dy * jvy + dz * jvz        -- the way the spray runs across the texture
        local l = sqrt(du * du + dv * dv)
        if l > 1e-9 then du, dv = du / l, dv / l else du, dv = 0, 1 end
        local s = sqrt((jux * jux + juy * juy + juz * juz + jvx * jvx + jvy * jvy + jvz * jvz) / 2)
        local rel = 0.3 + 0.7 * sin(phi * 0.9 + 0.2) ^ 2                                      -- the rear of the tyre throws most
        n = n + 1
        hits[n] = { u = u, v = v, weight = exp(-dist / 0.9) * rel, dx = du, dy = dv, s = s, dist = dist }
      end
    end
    if yield and k % p.yieldEvery == 0 then yield() end
  end
  return { hits = hits, rays = p.rays, count = n }
end

-- opts: any of DEFAULTS. wheels as bodymap's; returns { wheels = { [i] = { hits, rays, count } }, reach }
function M.bake(tris, wheels, opts)
  local p = {}
  for k, v in pairs(M.DEFAULTS) do p[k] = v end
  for k, v in pairs(opts or {}) do p[k] = v end
  local g = M.grid(tris, p.cell)
  local out = { wheels = {}, reach = p.reach, params = p }
  if not g then return out end
  for i, wheel in ipairs(wheels or {}) do out.wheels[i] = bakeWheel(g, wheel, p, p.yield) end
  return out
end

-- n splats of the wheel `wi` (nil: all wheels together) drawn by weight: { u, v, dx, dy, s, dist }; rnd() gives 0..1
function M.sample(bake, wi, n, rnd)
  local list, cum, total = {}, {}, 0
  for i, w in pairs(bake.wheels) do
    if wi == nil or wi == i then
      for _, h in ipairs(w.hits) do
        total = total + h.weight
        list[#list + 1] = h
        cum[#cum + 1] = total
      end
    end
  end
  local out = {}
  if total <= 0 then return out end
  for _ = 1, n do
    local r = rnd() * total
    local lo, hi = 1, #cum
    while lo < hi do local mid = floor((lo + hi) / 2) if cum[mid] >= r then hi = mid else lo = mid + 1 end end
    local h = list[lo]
    out[#out + 1] = { u = h.u, v = h.v, dx = h.dx, dy = h.dy, s = h.s, dist = h.dist }
  end
  return out
end

-- the fraction of rays that hit, per wheel (for the tests and the status line)
function M.hitRate(bake)
  local out = {}
  for i, w in pairs(bake.wheels) do out[i] = w.count / math.max(1, w.rays) end
  return out
end

return M
