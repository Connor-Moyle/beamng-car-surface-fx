-- Car Surface FX: the body map of a car. Built once from the car's own mesh (.dae): for every cell of the paint texture it knows where that bit of paint is on the car (its place and its
-- normal in the car's frame: x left, y back, z up), how high above the ground, which way it faces, and how far it is from each wheel. Every kind of dirt is a rule over this map, so a
-- splat is put where that kind of dirt really lands:
--   mud    sprayed off the tyres: the lower body, the sills, the panel just behind each wheel (more for the wheel that throws it), the underside; streaks along the spray
--   grime  the road film: the lower band of the whole body and the rear faces up to the height of the car's back (the vortex behind a hatch or an SUV)
--   dust   like grime, lighter, higher
--   rubber only around the wheels: the arch lips and the panel behind the wheel
--   bugs   forward-facing surfaces: the nose, the front of the bonnet, the base of the windscreen
--   snow   only on flat surfaces that face the sky and sit high: roof, bonnet, boot lid, the base of the windscreen; none on doors or other steep faces
-- The map is a grid over the paint texture (N x N cells), so a cell gives the splat's texture coordinates directly. Pure functions, tested outside the game.
local M = {}

local N = 64
M.N = N
local floor, sqrt, exp, max, min, abs = math.floor, math.sqrt, math.exp, math.max, math.min, math.abs

local function cross(ax, ay, az, bx, by, bz) return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx end

-- tris: { pos = {9 numbers}, uv = {6 numbers} } in the car frame; wheels: { { x, y, z, r }, ... } at rest. Returns the map.
function M.build(tris, wheels)
  local cells, cn = {}, {}
  local x0, x1, y0, y1, z0, z1 = 1e9, -1e9, 1e9, -1e9, 1e9, -1e9
  local cx, cy, cz, n = 0, 0, 0, 0
  for _, t in ipairs(tris) do
    for c = 0, 2 do
      local x, y, z = t.pos[c * 3 + 1], t.pos[c * 3 + 2], t.pos[c * 3 + 3]
      x0, x1, y0, y1, z0, z1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y), min(z0, z), max(z1, z)
      cx, cy, cz, n = cx + x, cy + y, cz + z, n + 1
    end
  end
  if n == 0 then return nil end
  cx, cy, cz = cx / n, cy / n, cz / n                                     -- the middle of the body: normals are turned to point away from it
  local map = { bounds = { x0, x1, y0, y1, z0, z1 }, wheels = wheels or {}, cells = {}, cache = {}, tris = #tris }
  for _, t in ipairs(tris) do
    local p, uv = t.pos, t.uv
    local e1x, e1y, e1z, e2x, e2y, e2z = p[4] - p[1], p[5] - p[2], p[6] - p[3], p[7] - p[1], p[8] - p[2], p[9] - p[3]
    local nx, ny, nz = cross(e1x, e1y, e1z, e2x, e2y, e2z)
    local area2 = sqrt(nx * nx + ny * ny + nz * nz)
    local udet = (uv[3] - uv[1]) * (uv[6] - uv[2]) - (uv[5] - uv[1]) * (uv[4] - uv[2])
    if area2 > 1e-9 and abs(udet) > 1e-12 then
      nx, ny, nz = nx / area2, ny / area2, nz / area2
      local mx, my, mz = (p[1] + p[4] + p[7]) / 3, (p[2] + p[5] + p[8]) / 3, (p[3] + p[6] + p[9]) / 3
      if nx * (mx - cx) + ny * (my - cy) + nz * (mz - cz) < 0 then nx, ny, nz = -nx, -ny, -nz end
      -- the gradients of u and v along the surface (3D vectors): how a direction in the car frame moves across the texture
      local g11, g12, g22 = e1x * e1x + e1y * e1y + e1z * e1z, e1x * e2x + e1y * e2y + e1z * e2z, e2x * e2x + e2y * e2y + e2z * e2z
      local det = g11 * g22 - g12 * g12
      local Ax, Ay, Az = (g22 * e1x - g12 * e2x) / det, (g22 * e1y - g12 * e2y) / det, (g22 * e1z - g12 * e2z) / det
      local Bx, By, Bz = (g11 * e2x - g12 * e1x) / det, (g11 * e2y - g12 * e1y) / det, (g11 * e2z - g12 * e1z) / det
      local du1, dv1, du2, dv2 = uv[3] - uv[1], uv[4] - uv[2], uv[5] - uv[1], uv[6] - uv[2]
      local jux, juy, juz = Ax * du1 + Bx * du2, Ay * du1 + By * du2, Az * du1 + Bz * du2
      local jvx, jvy, jvz = Ax * dv1 + Bx * dv2, Ay * dv1 + By * dv2, Az * dv1 + Bz * dv2
      local ux0, ux1 = min(uv[1], uv[3], uv[5]), max(uv[1], uv[3], uv[5])
      local uy0, uy1 = min(uv[2], uv[4], uv[6]), max(uv[2], uv[4], uv[6])
      local small = floor(ux0 * N) == floor(ux1 * N) and floor(uy0 * N) == floor(uy1 * N)
      for gy = max(0, floor(uy0 * N)), min(N - 1, floor(uy1 * N)) do
        for gx = max(0, floor(ux0 * N)), min(N - 1, floor(ux1 * N)) do
          local qx, qy = (gx + 0.5) / N, (gy + 0.5) / N
          local a = ((qx - uv[1]) * (uv[6] - uv[2]) - (uv[5] - uv[1]) * (qy - uv[2])) / udet
          local b = ((uv[3] - uv[1]) * (qy - uv[2]) - (qx - uv[1]) * (uv[4] - uv[2])) / udet
          if small or (a >= 0 and b >= 0 and a + b <= 1) then
            local k = gy * N + gx + 1
            local c = cells[k]
            if not c then c = { w = 0, nx = 0, ny = 0, nz = 0, px = 0, py = 0, pz = 0, jux = 0, juy = 0, juz = 0, jvx = 0, jvy = 0, jvz = 0, gx = gx, gy = gy } cells[k] = c end
            local aa = area2
            c.w = c.w + aa
            c.nx, c.ny, c.nz = c.nx + nx * aa, c.ny + ny * aa, c.nz + nz * aa
            local ax_, ay_, az_ = p[1] + a * e1x + b * e2x, p[2] + a * e1y + b * e2y, p[3] + a * e1z + b * e2z
            if small then ax_, ay_, az_ = mx, my, mz end
            c.px, c.py, c.pz = c.px + ax_ * aa, c.py + ay_ * aa, c.pz + az_ * aa
            c.jux, c.juy, c.juz, c.jvx, c.jvy, c.jvz = c.jux + jux * aa, c.juy + juy * aa, c.juz + juz * aa, c.jvx + jvx * aa, c.jvy + jvy * aa, c.jvz + jvz * aa
          end
        end
      end
    end
  end
  local list = {}
  for _, c in pairs(cells) do
    local w = c.w
    c.nx, c.ny, c.nz = c.nx / w, c.ny / w, c.nz / w
    local l = sqrt(c.nx * c.nx + c.ny * c.ny + c.nz * c.nz)
    if l > 1e-9 then c.nx, c.ny, c.nz = c.nx / l, c.ny / l, c.nz / l end
    c.px, c.py, c.pz = c.px / w, c.py / w, c.pz / w
    c.jux, c.juy, c.juz, c.jvx, c.jvy, c.jvz = c.jux / w, c.juy / w, c.juz / w, c.jvx / w, c.jvy / w, c.jvz / w
    c.h = (c.pz - z0) / max(0.01, z1 - z0)                                -- 0 at the lowest point of the body, 1 at the roof
    list[#list + 1] = c
  end
  map.list = list
  return map
end

-- ---- the rules: a weight per cell for a kind of dirt. wheel = index of the wheel that throws it (mud, rubber) or nil for all wheels
local function nearWheel(map, c, wi)
  local best, bi = 1e9, nil
  for i, wh in ipairs(map.wheels) do
    if wi == nil or wi == i then
      local d = sqrt((c.px - wh.x) ^ 2 + (c.py - wh.y) ^ 2 + (c.pz - wh.z) ^ 2)
      if d < best then best, bi = d, i end
    end
  end
  return best, bi
end

-- how far behind the wheel's centre this bit of body sits (m, along the car; + = behind), and how far to the side of the wheel's plane
local function behind(map, c, wi)
  local wh = map.wheels[wi]
  if not wh then return -9, 9 end
  return c.py - wh.y, abs(c.px - wh.x)
end

local RULES = {}
function RULES.mud(map, c, wi)
  local base = exp(-c.h / 0.22)                                           -- mostly low
  local up = c.nz > 0.7 and 0.15 or 1                                     -- little on flat upward faces
  local w = base * up * 0.25
  if wi then                                                              -- the wheel that throws it: the panel behind it and its arch
    local dy, dx = behind(map, c, wi)
    local wh = map.wheels[wi]
    local dz = c.pz - wh.z
    if dy > -0.3 and dy < 1.6 and dx < 0.9 then w = w + exp(-(dy - 0.45) ^ 2 / 0.5) * exp(-max(0, dz) / 0.5) * up * 1.0 end
    if dy > -0.2 and dy < 0.9 and dx < 0.9 and c.nz < -0.2 then w = w + 0.5 end                          -- the underside near the wheel
  else
    local d = nearWheel(map, c)
    w = w * (1 + 2.5 * exp(-d / 0.8))
  end
  return w
end
function RULES.grime(map, c)
  local w = exp(-c.h / 0.32) * (c.nz > 0.7 and 0.2 or 1)
  if c.ny > 0.5 and c.h < 0.85 then w = w + 1.2 * (0.4 + 0.6 * (1 - c.h)) end                          -- a rear face: the vortex behind the car puts the road film on it, fading upward
  return w
end
function RULES.dust(map, c)
  return (exp(-c.h / 0.55) * (c.nz > 0.7 and 0.4 or 1)) + (c.ny > 0.5 and c.h < 0.9 and 0.6 or 0)
end
function RULES.rubber(map, c, wi)
  local d = nearWheel(map, c, wi)
  if d > 0.95 then return 0 end
  local dy = behind(map, c, wi or select(2, nearWheel(map, c)))
  return exp(-d / 0.4) * (dy > -0.15 and 1 or 0.25)                       -- the arch lip and the panel behind the spinning wheel
end
function RULES.bugs(map, c)
  if c.ny > -0.4 then return 0 end                                        -- forward-facing: the nose, the front of the bonnet, the base of the windscreen
  return exp(-abs(c.h - 0.5) / 0.3) + (c.nz > 0.3 and c.h > 0.5 and 0.4 or 0)
end
function RULES.snow(map, c)
  if c.nz < 0.78 or c.h < 0.4 then return 0 end                           -- doors and vertical faces get none, a steep bit lets it slide off
  return c.nz ^ 10
end
M.RULES = RULES

-- the cumulative weights of a kind (cached per kind and wheel)
local function table_for(map, kind, wi)
  local key = kind .. ':' .. tostring(wi)
  local t = map.cache[key]
  if t then return t end
  local rule = RULES[kind]
  t = { total = 0, cum = {} }
  if rule then
    for _, c in ipairs(map.list) do
      local w = rule(map, c, wi) * c.w
      if w > 1e-9 then t.total = t.total + w end
      t.cum[#t.cum + 1] = t.total
    end
  end
  map.cache[key] = t
  return t
end

-- n splats of a kind: { u, v, dx, dy, s } with u, v texture coordinates (0..1), dx, dy the direction of the spray on the texture (unit, mud only), s texture units per metre.
-- rnd() is a function that returns 0..1. wi: the wheel that throws it (mud, rubber).
function M.sample(map, kind, n, rnd, wi)
  local out = {}
  local t = table_for(map, kind, wi)
  if t.total <= 0 or #t.cum == 0 then return out end
  for _ = 1, n do
    local r = rnd() * t.total
    local lo, hi = 1, #t.cum
    while lo < hi do local mid = floor((lo + hi) / 2) if t.cum[mid] >= r then hi = mid else lo = mid + 1 end end
    local c = map.list[lo]
    local s = {}
    s.u, s.v = (c.gx + rnd()) / N, (c.gy + rnd()) / N
    s.s = sqrt((c.jux ^ 2 + c.juy ^ 2 + c.juz ^ 2 + c.jvx ^ 2 + c.jvy ^ 2 + c.jvz ^ 2) / 2)
    if kind == 'mud' then                                                  -- along the spray: thrown backward and up from the tread
      local dux, dvx = c.jux * 0 + c.juy * 1 + c.juz * 0.5, c.jvx * 0 + c.jvy * 1 + c.jvz * 0.5
      local l = sqrt(dux * dux + dvx * dvx)
      if l > 1e-9 then s.dx, s.dy = dux / l, dvx / l else s.dx, s.dy = 0, 1 end
    end
    out[#out + 1] = s
  end
  return out
end

-- how much of the body a kind could land on (0..1 of the cell count): for the tests and the status line
function M.coverage(map, kind, wi)
  local t = table_for(map, kind, wi)
  local prev, count = 0, 0
  for _, cum in ipairs(t.cum) do if cum > prev then count = count + 1 end prev = cum end
  return count / math.max(1, #map.list)
end

return M
