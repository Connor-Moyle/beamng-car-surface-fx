-- carSurfaceFxTyreLook.lua with a mocked car: each wheel's own tyre mesh is found by the node list of its flexbody, the stage goes up to the game side as a call with the wheel's meshes, the belts make the tread METAL.
local sent, metal, events = {}, {}, {}
local names = dofile('mod/lua/common/csfx_tyrelook_names.lua')
assert(#names >= 1 and names[1], 'the list of tyre materials is generated')
wheels = { wheels = { [0] = { name = 'FL', node1 = 50, treadNodes = { 1, 2 } }, [1] = { name = 'FR', node1 = 51, treadNodes = { 3, 4 } } } }
-- the mesh order is the reverse of the wheel order on purpose
v = { data = { _materials = { triggers = {} }, flexbodies = { { mesh = 'tire_01a_15x7_24', _group_nodes = { 3, 4, 51 } }, { mesh = 'tire_01a_15x7_24D', _group_nodes = { 1, 2, 50 } }, { mesh = 'body', _group_nodes = { 9 } } } } }
particles = { materials = {}, getMaterialIDByName = function() return 2 end }
obj = { getMeshesContainingMaterial = function(_, m) return m == 'tire_01a' and 'tire_01a_15x7_24 tire_01a_15x7_24D other' or '' end,
  queueGameEngineLua = function(_, c) if c:find('look(', 1, true) then sent[#sent + 1] = c else events[#events + 1] = c end end, getId = function() return 7 end, setNodeMaterial = function(_, cid, id) metal[cid] = id end }
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
assert(events[1]:find('lookEvent(7,0,"metal","2 nodes, material id 2, 0 failed")', 1, true), 'the METAL switch is reported to the game side for its log: ' .. tostring(events[1]))
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
-- a failing engine call is reported, not swallowed
obj.setNodeMaterial = function() error('boom') end
particles.getMaterialIDByName = function() error('no list') end
L.set(1, 5)
assert(events[#events]:find('lookEvent(7,1,"metal","2 nodes, material id 2, 2 failed: ', 1, true), 'failures are reported to the game side: ' .. tostring(events[#events]))
-- a flip that could not be made the first time (the wheel's nodes not ready) is made by the next report, though the stage has not changed
wheels.wheels[0].treadNodes = nil
L.restore()
L.set(0, 5, true)
wheels.wheels[0].treadNodes = { 1, 2 }
obj.setNodeMaterial = function(_, cid, id) metal[cid] = id end
particles.getMaterialIDByName = function() return 2 end
metal[1], metal[2] = nil, nil
L.set(0, 5, true)
assert(metal[1] == 2 and metal[2] == 2, 'the nodes become METAL on the next report once they exist')
-- a flip that failed on some nodes is retried (and said once), and succeeds when the calls work again
local fails, nsent = 1, #events
obj.setNodeMaterial = function(_, cid, id) if fails > 0 then error('refused') end metal[cid] = id end
metal[1], metal[2] = nil, nil
L.restore()
L.set(0, 5, true)
L.set(0, 5, true)
L.set(0, 5, true)
local said = 0 for k = nsent + 1, #events do if events[k]:find('refused', 1, true) then said = said + 1 end end
assert(said == 1, 'a failing flip is said once, not on every report: ' .. said)
fails = 0
L.set(0, 5, true)
assert(metal[1] == 2 and metal[2] == 2, 'retried and done when the calls work again')
