-- The spray tracing (carSurfaceFx/spraytrace.lua): the grid finds the same first hit as brute force, and the baked hits land where a tyre's spray lands on a box car.
local S = require('carSurfaceFx/spraytrace')
local B = require('carSurfaceFx/bodymap')

local X0, X1, Y0, Y1, Z0, Z1 = -0.9, 0.9, -2, 2, 0.2, 1.4
local function quad(p1, p2, p3, p4, u0, v0, u1, v1, out)
  out[#out + 1] = { pos = { p1[1], p1[2], p1[3], p2[1], p2[2], p2[3], p3[1], p3[2], p3[3] }, uv = { u0, v0, u1, v0, u1, v1 } }
  out[#out + 1] = { pos = { p1[1], p1[2], p1[3], p3[1], p3[2], p3[3], p4[1], p4[2], p4[3] }, uv = { u0, v0, u1, v1, u0, v1 } }
end
local tris = {}
quad({ X0, Y0, Z1 }, { X1, Y0, Z1 }, { X1, Y1, Z1 }, { X0, Y1, Z1 }, 0, 0, 1 / 3, 0.5, tris)          -- top
quad({ X0, Y0, Z0 }, { X1, Y0, Z0 }, { X1, Y1, Z0 }, { X0, Y1, Z0 }, 1 / 3, 0, 2 / 3, 0.5, tris)      -- underside
quad({ X1, Y0, Z0 }, { X1, Y1, Z0 }, { X1, Y1, Z1 }, { X1, Y0, Z1 }, 2 / 3, 0, 1, 0.5, tris)          -- left
quad({ X0, Y0, Z0 }, { X0, Y1, Z0 }, { X0, Y1, Z1 }, { X0, Y0, Z1 }, 0, 0.5, 1 / 3, 1, tris)          -- right
quad({ X0, Y0, Z0 }, { X1, Y0, Z0 }, { X1, Y0, Z1 }, { X0, Y0, Z1 }, 1 / 3, 0.5, 2 / 3, 1, tris)      -- front
quad({ X0, Y1, Z0 }, { X1, Y1, Z0 }, { X1, Y1, Z1 }, { X0, Y1, Z1 }, 2 / 3, 0.5, 1, 1, tris)          -- back
-- wheels outside the box sides, in line with its corners (a car's wheels sit outside its sill)
local wheels = { { x = 1.0, y = -1.3, z = 0.35, r = 0.35, w = 0.2 }, { x = -1.0, y = -1.3, z = 0.35, r = 0.35, w = 0.2 },
                 { x = 1.0, y = 1.3, z = 0.35, r = 0.35, w = 0.2 }, { x = -1.0, y = 1.3, z = 0.35, r = 0.35, w = 0.2 } }

local seed = 99
local function rnd() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end

-- the grid against brute force
local g = S.grid(tris, 0.2)
local function brute(ox, oy, oz, sx, sy, sz)
  local bestT
  for i, t in ipairs(tris) do
    local p = t.pos
    local e1x, e1y, e1z, e2x, e2y, e2z = p[4] - p[1], p[5] - p[2], p[6] - p[3], p[7] - p[1], p[8] - p[2], p[9] - p[3]
    local px, py, pz = sy * e2z - sz * e2y, sz * e2x - sx * e2z, sx * e2y - sy * e2x
    local det = e1x * px + e1y * py + e1z * pz
    if math.abs(det) > 1e-12 then
      local inv = 1 / det
      local tx, ty, tz = ox - p[1], oy - p[2], oz - p[3]
      local a = (tx * px + ty * py + tz * pz) * inv
      if a >= 0 and a <= 1 then
        local qx, qy, qz = ty * e1z - tz * e1y, tz * e1x - tx * e1z, tx * e1y - ty * e1x
        local b = (sx * qx + sy * qy + sz * qz) * inv
        if b >= 0 and a + b <= 1 then
          local t = (e2x * qx + e2y * qy + e2z * qz) * inv
          if t >= 0 and t <= 1 and (not bestT or t < bestT) then bestT = t end
        end
      end
    end
  end
  return bestT
end
local agree, hitsN = 0, 0
for _ = 1, 400 do
  local ox, oy, oz = rnd() * 4 - 2, rnd() * 6 - 3, rnd() * 2
  local sx, sy, sz = rnd() * 1.2 - 0.6, rnd() * 1.2 - 0.6, rnd() * 1.2 - 0.6
  local t1 = S.segment(g, ox, oy, oz, sx, sy, sz)
  local t2 = brute(ox, oy, oz, sx, sy, sz)
  if (t1 == nil) == (t2 == nil) and (t1 == nil or math.abs(t1 - t2) < 1e-9) then agree = agree + 1 end
  if t2 then hitsN = hitsN + 1 end
end
assert(agree == 400 and hitsN > 20, 'the grid and brute force find the same first hits: ' .. agree .. ' of 400, ' .. hitsN .. ' hits')
assert(S.grid({}, 0.2) == nil and next(S.bake({}, wheels).wheels) == nil, 'no triangles: nothing, no error')

-- the baked hits
local function bake(opts) return S.bake(tris, wheels, opts) end
local b = bake({ speed = 20 })
local rate = S.hitRate(b)
for i = 1, 4 do
  assert(b.wheels[i] and rate[i] > 0.2, 'wheel ' .. i .. ' hits the body: ' .. tostring(rate[i]))
  for _, h in ipairs(b.wheels[i].hits) do
    assert(h.u >= -1e-6 and h.u <= 1 + 1e-6 and h.v >= -1e-6 and h.v <= 1 + 1e-6, 'a hit is on the texture')
    assert(h.dist <= S.DEFAULTS.reach + 1e-6 and h.weight > 0 and h.weight <= 1, 'within reach, a weight')
    assert(math.abs(h.dx * h.dx + h.dy * h.dy - 1) < 1e-6, 'the direction on the texture is a unit vector')
  end
end
-- where it lands: a front wheel's spray goes back and up: the side beside and behind it and the underside, not the front face
local map = B.build(tris, wheels)
local function cellAt(u, v)
  local gx, gy = math.floor(u * B.N), math.floor(v * B.N)
  for _, c in ipairs(map.list) do if c.gx == gx and c.gy == gy then return c end end
end
local function kinds(list)
  local front, side, under, rear, top = 0, 0, 0, 0, 0
  for _, s in ipairs(list) do
    local c = cellAt(s.u, s.v)
    if c then
      if c.ny < -0.7 then front = front + 1 elseif c.nz < -0.7 then under = under + 1 elseif c.nz > 0.7 then top = top + 1 elseif c.ny > 0.7 then rear = rear + 1 else side = side + 1 end
    end
  end
  local n = math.max(1, #list)
  return front / n, side / n, under / n, rear / n, top / n
end
local sf = S.sample(b, 1, 600, rnd)                      -- wheel 1: front left
local front, side, under = kinds(sf)
assert(#sf == 600 and front < 0.03 and side + under > 0.9, 'front wheel spray: not the front face, mostly the side and the underside: ' .. front .. ' ' .. side .. ' ' .. under)
local sr = S.sample(b, 3, 600, rnd)                      -- wheel 3: rear left
local f3, s3, u3, r3 = kinds(sr)
assert(f3 < 0.03 and s3 + u3 > 0.9, 'rear wheel spray: the side and the underside')

-- the throw: faster and spinning reaches further; the weight falls with the distance
local function dists(opts)
  local bk = bake(opts)
  local list = {}
  for _, w in pairs(bk.wheels) do for _, h in ipairs(w.hits) do list[#list + 1] = h.dist end end
  table.sort(list)
  return list
end
local function p90(list) return list[math.max(1, math.floor(#list * 0.9))] end
local slow, fast = dists({ speed = 4 }), dists({ speed = 30 })
local spin, calm = dists({ speed = 10, slip = 1 }), dists({ speed = 10, slip = 0 })
assert(p90(fast) > p90(slow), 'faster: the spray reaches further (' .. p90(slow) .. ' against ' .. p90(fast) .. ')')
local function firstStep(p) local pts = S.path(wheels[1], math.pi / 2, 0, 0, p, function() return 0.5 end) return math.sqrt((pts[2][1] - pts[1][1]) ^ 2 + (pts[2][2] - pts[1][2]) ^ 2 + (pts[2][3] - pts[1][3]) ^ 2) end
local P0, P1 = { width = 0.22, speed = 10, slip = 0, reach = 2.5 }, { width = 0.22, speed = 10, slip = 1, reach = 2.5 }
assert(firstStep(P1) > firstStep(P0) * 1.5, 'wheelspin throws faster: the first step of the path is longer')
local up = S.path(wheels[1], math.pi / 2, 0, 0, P0, function() return 0.5 end)
assert(up[2][3] > up[1][3] and up[#up][2] > up[2][2], 'off the rear of the tyre a lump goes up, and the air carries it back')
local topPath = S.path(wheels[1], 0, 0, 0, P0, function() return 0.5 end)
assert(topPath[2][2] < topPath[1][2], 'off the top it goes forward')
local low = S.path(wheels[1], math.pi, 0, 0, P0, function() return 0.5 end)
assert(low[2][2] > low[1][2], 'off the underside it goes backward')
local near, far, nn, nf = 0, 0, 0, 0
for _, h in ipairs(b.wheels[3].hits) do
  if h.dist < 0.7 then near, nn = near + h.weight, nn + 1 elseif h.dist > 1.4 then far, nf = far + h.weight, nf + 1 end
end
assert(nn > 0 and nf > 0 and near / nn > far / nf, 'a hit near the wheel weighs more than a far one')
-- the reach limit
local short = S.bake(tris, wheels, { reach = 0.6, speed = 20 })
for _, w in pairs(short.wheels) do for _, h in ipairs(w.hits) do assert(h.dist <= 0.6 + 1e-6, 'nothing beyond the reach') end end
-- same seed, same hits; the sample draws what was asked
local b2 = bake({ speed = 20 })
assert(b2.wheels[1].count == b.wheels[1].count, 'baking is repeatable')
assert(#S.sample(b, nil, 50, rnd) == 50 and #S.sample({ wheels = {} }, nil, 5, rnd) == 0, 'sample')
-- yielding: the caller can spread the work
local yields = 0
S.bake(tris, { wheels[1] }, { rays = 100, yield = function() yields = yields + 1 end, yieldEvery = 10 })
assert(yields == 10, 'a yield every few rays: ' .. yields)
print('carSurfaceFx spraytrace: ok')
