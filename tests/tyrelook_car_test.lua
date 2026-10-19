-- carSurfaceFxTyreLook.lua with a mocked car: each wheel's own tyre mesh is found by the node list of its flexbody, the stage goes up to the game side as a call with the wheel's meshes, the belts make the tread METAL.
local sent, metal = {}, {}
local names = dofile('mod/lua/common/csfx_tyrelook_names.lua')
assert(#names >= 40 and names[1], 'the list of tyre materials is generated')
wheels = { wheels = { [0] = { name = 'FL', node1 = 50, treadNodes = { 1, 2 } }, [1] = { name = 'FR', node1 = 51, treadNodes = { 3, 4 } } } }
-- the mesh order is the reverse of the wheel order on purpose
v = { data = { flexbodies = { { mesh = 'tire_01a_15x7_24', _group_nodes = { 3, 4, 51 } }, { mesh = 'tire_01a_15x7_24D', _group_nodes = { 1, 2, 50 } }, { mesh = 'body', _group_nodes = { 9 } } } } }
particles = { materials = {}, getMaterialIDByName = function() return 2 end }
obj = { getMeshesContainingMaterial = function(_, m) return m == 'tire_01a' and 'tire_01a_15x7_24 tire_01a_15x7_24D other' or '' end,
  queueGameEngineLua = function(_, c) sent[#sent + 1] = c end, getId = function() return 7 end, setNodeMaterial = function(_, cid, id) metal[cid] = id end }
package.loaded['csfx_tyrelook_names'] = names
local L = dofile('mod/lua/vehicle/extensions/carSurfaceFxTyreLook.lua')
L.set(0, 2)
assert(#sent == 1 and sent[1]:find('carSurfaceFx_tyres.look(7,0,2,{{"tire_01a","tire_01a_15x7_24D"}})', 1, true), 'wheel 0 sends its own mesh: ' .. tostring(sent[1]))
L.set(1, 4) L.set(0, 5)
assert(sent[2]:find('look(7,1,4,{{"tire_01a","tire_01a_15x7_24"}})', 1, true) and sent[3]:find('look(7,0,5,', 1, true), 'each wheel has its own stage')
assert(metal[1] == 2 and metal[2] == 2 and metal[3] == nil, 'belts: METAL on that tyre only')
L.set(0, 0)
assert(sent[4]:find('look(7,0,0,', 1, true) and metal[1] == 4, 'new again: stage 0 up to the game side and rubber nodes back')
L.set(0, 0)
assert(#sent == 4, 'no repeat while the stage is the same')
L.set(0, 3) L.restore()
assert(L.stages() == '', 'restore puts everything back')
assert(L.info() == '0:tire_01a@tire_01a_15x7_24D 1:tire_01a@tire_01a_15x7_24', 'info lists the meshes: ' .. L.info())
print('carSurfaceFxTyreLook: ok')
