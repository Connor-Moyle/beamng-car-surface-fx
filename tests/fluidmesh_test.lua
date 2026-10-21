-- The glossy leak puddles (carSurfaceFx/fluidmesh.lua) against a mocked engine: a plane per puddle, grown with it, deleted with it, decals left out where a plane stands.
local R = require('carSurfaceFx/fluidrules')
local objects, created, deleted = {}, 0, 0
function vec3(x, y, z) return { x = x, y = y, z = z } end
function castRayStatic(origin) return 2 end                    -- the ground is 2 m under the start (z = start - 2)
be = { getSurfaceHeightBelow = function() return 0 end }
scenetree = { findObject = function(name) return {} end, MissionGroup = { addObject = function() end } }
function loadJsonMaterialsFile() end
function createObject(class)
  assert(class == 'ProceduralMesh', 'only planes are made')
  local o = { pos = nil, scale = nil, meshes = nil }
  function o:registerObject(name) self.name = name end
  function o:createMesh(m) self.meshes = m created = created + 1 end
  function o:setPosition(v) self.pos = v end
  function o:setScale(v) self.scale = v end
  function o:setPosRot(x, y, z, qx, qy, qz, qw) self.rot = { qz, qw } end
  function o:delete() self.dead = true deleted = deleted + 1 end
  objects[#objects + 1] = o
  return o
end

local M = dofile('mod/lua/ge/extensions/carSurfaceFx/fluidmesh.lua')
require('carSurfaceFx/gpugate').reset()                        -- (the smoke test before this one reported material reloads: the gate would hold)
local cfg = R.defaults()
local store = R.newStore(6)
local p = R.drip(store, 10, 20, 0, 'oil', 1, cfg, false, 0.5)
p.r = 0.5
M.sync(store, cfg, 10, 20)
assert(p.meshed and M.count() == 1, 'a puddle near the camera gets a plane')
local oilPlane, sheen = objects[1], objects[2]
local mesh = oilPlane.meshes[1][1]
assert(mesh.material == 'csfx_puddle_oil' and #mesh.verts == 25 and #mesh.faces == 96, 'a 5 x 5 grid in the oil material')
assert(sheen and sheen.meshes[1][1].material == 'csfx_puddle_sheen', 'oil carries the rainbow plane')
assert(oilPlane.pos.z == 0.03 and sheen.pos.z == 0.045 and oilPlane.pos.x == 10, 'the planes lie just above the ground at the puddle')
assert(sheen.rot and math.abs(sheen.rot[1] ^ 2 + sheen.rot[2] ^ 2 - 1) < 1e-9, 'the sheen plane turns with the camera near the puddle')
local k1 = oilPlane.scale.x
p.r = 0.7
M.sync(store, cfg, 10, 20)
assert(oilPlane.scale.x > k1, 'the plane grows with the puddle')
p.r = 1.4                                                      -- past the corners it was sampled for: a new plane
M.sync(store, cfg, 10, 20)
assert(oilPlane.dead and M.count() == 1, 'a plane outgrown is rebuilt')
local c = R.drip(store, 14, 20, 0, 'coolant', 1, cfg, false, 0.5)
c.r = 0.3
local s = R.drip(store, 16, 20, 0, 'oil', 1, cfg, true, 0.5)   -- a drip spot of a moving car
M.sync(store, cfg, 10, 20)
assert(c.meshed and not s.meshed, 'coolant gets a plane, a drip spot stays a decal')
M.sync(store, cfg, 500, 500)
assert(not c.meshed and M.count() == 0, 'far from the camera no planes are kept')
M.sync(store, cfg, 10, 20)
local n = M.count()
for i = 1, 5 do R.drip(store, 30 + i * 3, 20, 0, 'oil', 1, cfg, false, 0.5) end
assert(R.ringFade(store, 1) <= 1, 'the ring fades its oldest')
M.clear()
assert(M.count() == 0 and not c.meshed, 'clear takes every plane away')
local q = R.newStore(4)
local a = R.drip(q, 0, 0, 0, 'oil', 1, cfg, false, 0.5)
local g1 = a.gen
for i = 1, 4 do R.drip(q, 5 * i, 0, 0, 'oil', 1, cfg, false, 0.5) end      -- the ring comes round: the slot of `a` is a new puddle
assert(a.gen ~= g1 and not a.meshed, 'a recycled slot is a new puddle')

-- the caps: one plane a pass, at most maxMeshes, only within M.RADIUS of the camera, and no plane made or taken away while the gate holds after a material reload
local G = require('carSurfaceFx/gpugate')
M.clear() G.reset()
local st = R.newStore(10)
local cfg2 = R.defaults() cfg2.maxMeshes = 2
assert(cfg2.meshes == false and R.defaults().maxMeshes == 12, 'glossy planes are off by default and capped at 12')
for i = 1, 3 do R.drip(st, i * 5, 0, 0, 'coolant', 1, cfg2, false, 0.5).r = 0.4 end
local far = R.drip(st, 50, 0, 0, 'coolant', 1, cfg2, false, 0.5) far.r = 0.4     -- 50 m off: inside the decal cull (70) but outside the plane radius (40)
M.sync(st, cfg2, 0, 0)
assert(M.count() == 1, 'one plane a pass')
M.sync(st, cfg2, 0, 0) M.sync(st, cfg2, 0, 0)
assert(M.count() == 2 and not far.meshed, 'the cap holds and the far puddle stays a decal')
G.reloaded(os.clock())
cfg2.maxMeshes = 3
M.sync(st, cfg2, 0, 0)
assert(M.count() == 2, 'after a material reload no plane is made')
G.reset()
M.sync(st, cfg2, 0, 0)
assert(M.count() == 3 and G.lastPlanes() > 0, 'the gate opens again and is told of the plane')
G.reloaded(os.clock())
M.sync(st, cfg2, 500, 500)
assert(M.count() == 3, 'nor taken away while the gate holds')
G.reset()
M.sync(st, cfg2, 500, 500)
assert(M.count() == 1, 'two a pass taken away when it opens')
M.sync(st, cfg2, 500, 500)
assert(M.count() == 0, 'and the rest the pass after')
M.clear() G.reset()
print('carSurfaceFx fluidmesh: ok')
