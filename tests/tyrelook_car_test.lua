-- carSurfaceFxTyreLook.lua with a mocked car: each wheel's own tyre mesh is found by the node list of its flexbody, the stage goes up to the game side as a call with the wheel's meshes, the tread stays rubber at every stage (a METAL flip would drop the wheel's tyre force).
local sent, events, flips = {}, {}, 0
local names = dofile('mod/lua/common/csfx_tyrelook_names.lua')
assert(#names >= 1 and names[1], 'the list of tyre materials is generated')
wheels = { wheels = { [0] = { name = 'FL', node1 = 50, treadNodes = { 1, 2 } }, [1] = { name = 'FR', node1 = 51, treadNodes = { 3, 4 } } } }
-- the mesh order is the reverse of the wheel order on purpose
v = { data = { _materials = { triggers = {} }, flexbodies = { { mesh = 'tire_01a_15x7_24', _group_nodes = { 3, 4, 51 } }, { mesh = 'tire_01a_15x7_24D', _group_nodes = { 1, 2, 50 } }, { mesh = 'body', _group_nodes = { 9 } } } } }
particles = { materials = {}, getMaterialIDByName = function() return 2 end }
obj = { getMeshesContainingMaterial = function(_, m) return m == 'tire_01a' and 'tire_01a_15x7_24 tire_01a_15x7_24D other' or '' end,
  queueGameEngineLua = function(_, c) if c:find('look(', 1, true) then sent[#sent + 1] = c else events[#events + 1] = c end end, getId = function() return 7 end, setNodeMaterial = function() flips = flips + 1 end }
package.loaded['csfx_tyrelook_names'] = names
local L = dofile('mod/lua/vehicle/extensions/carSurfaceFxTyreLook.lua')
L.set(0, 2)
assert(#sent == 1 and sent[1]:find('carSurfaceFx_tyres.look(7,0,2,{{"tire_01a","tire_01a_15x7_24D"}})', 1, true), 'wheel 0 sends its own mesh: ' .. tostring(sent[1]))
L.set(1, 4) L.set(0, 5)
assert(sent[2]:find('look(7,1,4,{{"tire_01a","tire_01a_15x7_24"}})', 1, true) and sent[3]:find('look(7,0,5,', 1, true), 'each wheel has its own stage')
assert(flips == 0, 'the belts do not turn the tread to metal')
L.set(0, 0)
assert(sent[4]:find('look(7,0,0,', 1, true), 'new again: stage 0 up to the game side')
L.set(0, 0)
assert(#sent == 4, 'no repeat while the stage is the same')
L.set(0, 3) L.restore()
assert(L.stages() == '', 'restore puts everything back')
assert(flips == 0 and #events == 0, 'no node material is touched and nothing is reported')
assert(L.info() == '0:tire_01a@tire_01a_15x7_24D 1:tire_01a@tire_01a_15x7_24 glow=0', 'info lists the meshes: ' .. L.info())
print('carSurfaceFxTyreLook: ok')
-- a stage set by hand is not undone by the tyre module's reports; restore() hands it back
L.set(1, 5)
local n = #sent
L.set(1, 0, true)
assert(#sent == n and L.stages():find('1=5', 1, true), 'the module reports do not override a stage set by hand')
L.restore()
L.set(1, 2, true)
assert(L.stages() == '1=2', 'after restore the reports drive it again')
-- the wheel is found by the car's own name, whatever the key order of its jbeam: the same name lands on the same tyre with the keys swapped
for _, order in ipairs({ { FL = 0, FR = 1 }, { FL = 1, FR = 0 } }) do
  wheels = { wheels = { [order.FL] = { name = 'FL', node1 = 50, treadNodes = { 1, 2 } }, [order.FR] = { name = 'FR', node1 = 51, treadNodes = { 3, 4 } } } }
  sent = {}
  local M2 = dofile('mod/lua/vehicle/extensions/carSurfaceFxTyreLook.lua')
  M2.set('fr', 3)
  assert(#sent == 1 and sent[1]:find(string.format('look(7,%d,3,{{"tire_01a","tire_01a_15x7_24"}})', order.FR), 1, true), 'FR by name, keys ' .. order.FL .. '/' .. order.FR .. ': ' .. tostring(sent[1]))
end
print('carSurfaceFxTyreLook by wheel name: ok')
