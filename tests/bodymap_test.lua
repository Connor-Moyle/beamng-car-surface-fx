-- The body map (carSurfaceFx/bodymap.lua): a box car with six faces on a texture atlas, four wheels; each kind of dirt must land where it really lands.
local B = require('carSurfaceFx/bodymap')

-- a box x -0.9..0.9 (left +), y -2..2 (back +), z 0.2..1.4; each face gets a rectangle of the texture, uv in 0..1
local X0, X1, Y0, Y1, Z0, Z1 = -0.9, 0.9, -2, 2, 0.2, 1.4
local function quad(p1, p2, p3, p4, u0, v0, u1, v1, out)
  out[#out + 1] = { pos = { p1[1], p1[2], p1[3], p2[1], p2[2], p2[3], p3[1], p3[2], p3[3] }, uv = { u0, v0, u1, v0, u1, v1 } }
  out[#out + 1] = { pos = { p1[1], p1[2], p1[3], p3[1], p3[2], p3[3], p4[1], p4[2], p4[3] }, uv = { u0, v0, u1, v1, u0, v1 } }
end
local tris = {}
-- the faces in a 3 x 2 atlas: top (0,0), bottom (1,0), left (2,0), right (0,1), front (1,1), back (2,1)
quad({ X0, Y0, Z1 }, { X1, Y0, Z1 }, { X1, Y1, Z1 }, { X0, Y1, Z1 }, 0, 0, 1 / 3, 0.5, tris)
quad({ X0, Y0, Z0 }, { X1, Y0, Z0 }, { X1, Y1, Z0 }, { X0, Y1, Z0 }, 1 / 3, 0, 2 / 3, 0.5, tris)
quad({ X1, Y0, Z0 }, { X1, Y1, Z0 }, { X1, Y1, Z1 }, { X1, Y0, Z1 }, 2 / 3, 0, 1, 0.5, tris)
quad({ X0, Y0, Z0 }, { X0, Y1, Z0 }, { X0, Y1, Z1 }, { X0, Y0, Z1 }, 0, 0.5, 1 / 3, 1, tris)
quad({ X0, Y0, Z0 }, { X1, Y0, Z0 }, { X1, Y0, Z1 }, { X0, Y0, Z1 }, 1 / 3, 0.5, 2 / 3, 1, tris)
quad({ X0, Y1, Z0 }, { X1, Y1, Z0 }, { X1, Y1, Z1 }, { X0, Y1, Z1 }, 2 / 3, 0.5, 1, 1, tris)
local wheels = { { x = 0.8, y = -1.3, z = 0.35, r = 0.35 }, { x = -0.8, y = -1.3, z = 0.35, r = 0.35 }, { x = 0.8, y = 1.3, z = 0.35, r = 0.35 }, { x = -0.8, y = 1.3, z = 0.35, r = 0.35 } }
local map = B.build(tris, wheels)
assert(map and #map.list > 200, 'the faces fill cells of the texture: ' .. tostring(map and #map.list))

local function cellAt(u, v)
  local gx, gy = math.floor(u * B.N), math.floor(v * B.N)
  for _, c in ipairs(map.list) do if c.gx == gx and c.gy == gy then return c end end
end
local c1 = cellAt(1 / 6, 0.25)
assert(c1 and c1.nz > 0.99 and c1.h > 0.99, 'a cell of the roof: faces up, at the top: ' .. tostring(c1 and c1.nz))
local c2 = cellAt(5 / 6, 0.25)
assert(c2 and c2.nx > 0.99, 'a cell of the left side faces left')
local c3 = cellAt(5 / 6, 0.75)
assert(c3 and c3.ny > 0.99, 'a cell of the back faces back')
local c4 = cellAt(0.5, 0.25)
assert(c4 and c4.nz < -0.99, 'a cell of the underside faces down')

local seed = 12345
local function rnd() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
local function stat(list)
  local n, h, ny, nz = #list, 0, 0, 0
  for _, s in ipairs(list) do
    local c = cellAt(s.u, s.v)
    h, ny, nz = h + c.h, ny + (c.ny > 0.5 and 1 or 0), nz + (c.nz > 0.7 and 1 or 0)
  end
  return h / n, ny / n, nz / n, n
end

-- snow: only on flat faces that face the sky, high up
local snow = B.sample(map, 'snow', 300, rnd)
local _, _, flat, n = stat(snow)
assert(n == 300 and flat == 1, 'snow lands only on the roof: ' .. flat)

-- mud thrown by the rear left wheel: low, and behind that wheel's middle
local mud = B.sample(map, 'mud', 400, rnd, 3)
local h, rear = stat(mud)
assert(h < 0.35, 'mud is low on the body: mean height ' .. h)
local py = 0
for _, s in ipairs(mud) do py = py + cellAt(s.u, s.v).py end
assert(py / #mud > 0.3, 'mud of a rear wheel is on the rear half: ' .. py / #mud)
assert(mud[1].dx and mud[1].dy and math.abs(mud[1].dx ^ 2 + mud[1].dy ^ 2 - 1) < 1e-6, 'a splat of mud has a streak direction')

-- rubber: only close to the wheel that spins
local rub = B.sample(map, 'rubber', 200, rnd, 3)
for _, s in ipairs(rub) do
  local c = cellAt(s.u, s.v)
  assert(math.sqrt((c.px - 0.8) ^ 2 + (c.py - 1.3) ^ 2 + (c.pz - 0.35) ^ 2) <= 1.1, 'rubber stays around its wheel')
end

-- grime: the lower band and the rear face, little on the roof
local gr = B.sample(map, 'grime', 400, rnd)
local gh, grear, gflat = stat(gr)
assert(gh < 0.4 and grear > 0.1 and gflat < 0.1, 'road film: low, on the rear face, not on the roof: ' .. gh .. ' ' .. grear .. ' ' .. gflat)

assert(B.coverage(map, 'snow') < B.coverage(map, 'grime'), 'snow covers less of the body than road film')
assert(#B.sample(B.build({}, {}) or { list = {}, cache = {} }, 'snow', 5, rnd) == 0, 'an empty map gives no splats')
print('carSurfaceFx body map: ok')
