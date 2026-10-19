-- carSurfaceFxTyreLook.lua with a mocked car: each wheel's own tyre mesh is switched by stage, the belts make the tread METAL, stage 0 gives the car's material back.
local switched, reset, metal = {}, {}, {}
local names = dofile('mod/lua/common/csfx_tyrelook_names.lua')
assert(#names >= 40 and names[1], 'the list of tyre materials is generated')
wheels = { wheels = { [0] = { name = 'FL', treadNodes = { 1, 2 } }, [1] = { name = 'FR', treadNodes = { 3, 4 } } } }
v = { data = { flexbodies = { { mesh = 'tire_01a_15x7_24', group = { 'wheel_FL', 'tire_FL' } }, { mesh = 'tire_01a_15x7_24_2', group = { 'wheel_FR', 'tire_FR' } }, { mesh = 'body', group = { 'covet_body' } } } } }
particles = { materials = {}, getMaterialIDByName = function() return 2 end }
obj = { getMeshesContainingMaterial = function(_, m) return m == 'tire_01a' and 'tire_01a_15x7_24 tire_01a_15x7_24_2 other' or '' end,
  getSwitchableMaterial = function(_, o, _, mesh) return mesh:find('_2$') and 11 or 10 end,
  switchMaterial = function(_, msc, m) switched[msc] = m end, resetMaterials = function(_, msc) reset[msc] = true end,
  setNodeMaterial = function(_, cid, id) metal[cid] = id end }
package.loaded['csfx_tyrelook_names'] = names
local L = dofile('mod/lua/vehicle/extensions/carSurfaceFxTyreLook.lua')
L.set(0, 2)
assert(switched[10] == 'csfx_tire_01a_s2' and switched[11] == nil, 'only the front left tyre changed')
L.set(1, 4) L.set(0, 5)
assert(switched[11] == 'csfx_tire_01a_s4' and switched[10] == 'csfx_tire_01a_s5', 'each wheel has its own stage')
assert(metal[1] == 2 and metal[2] == 2 and metal[3] == nil, 'belts: METAL on that tyre only')
L.set(0, 0)
assert(reset[10] and metal[1] == 4, 'new again: the car\'s material and rubber nodes back')
L.set(0, 3) L.restore()
assert(reset[10] and L.stages() == '', 'restore puts everything back')
print('carSurfaceFxTyreLook: ok')
assert(L.info() == '0:tire_01a#10 1:tire_01a#11', 'info lists the switches: ' .. L.info())
