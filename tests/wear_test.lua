-- Body wear: the car-side sorting of contacts (vehicle/extensions/carSurfaceFxWear.lua) and the game-side counts and drawing (carSurfaceFx/bodywear.lua), against mocks.
local sent, simTime, handler = {}, 0, nil
function log() end
v = { data = { refNodes = { [0] = { ref = 1, left = 2, back = 3, up = 4 } } } }
local nodePos = { [1] = { x = 0, y = 0, z = 0 }, [2] = { x = 1, y = 0, z = 0 }, [3] = { x = 0, y = 1, z = 0 }, [4] = { x = 0, y = 0, z = 1 } }
obj = { getSimTime = function() return simTime end, getId = function() return 7 end, queueGameEngineLua = function(_, cmd) sent[#sent + 1] = cmd end,
  getNodePosition = function(_, id) return nodePos[id] end }
carSurfaceFxContact = { subscribe = function(_, fn) handler = fn end, unsubscribe = function() handler = nil end, setActive = function() end, isWheelNode = function(id) return id == 99 end }

local W = dofile('mod/lua/vehicle/extensions/carSurfaceFxWear.lua')
assert(W.classify(0.95, 10) == 'ground' and W.classify(0.1, 10) == 'wall' and W.classify(0.1, 2) == 'vehicle' and W.classify(nil, 2) == 'unknown', 'ground, wall, vehicle by normal and material')
assert(W.reject(false, 4, 10, 5000, 5) == 'tyre' and W.reject(true, 2, 10, 5000, 5) == 'wheel' and W.reject(false, 2, 10, 100, 5) == 'light' and W.reject(false, 2, 10, 5000, 0.2) == 'still'
  and W.reject(false, 2, 10, 5000, 5) == nil, 'a contact is a tyre, a wheel, light, not sliding, or a hit')
assert(W.severity(15000, 8) == 1 and W.severity(7500, 4) == 0.25 and W.severity(0, 8) == 0, 'severity from force and slip')

W.setConfig(true, false)
assert(handler, 'the wear subscribes to the shared contact wrapper')
local function ev(t) local e = { kind = 'node', node = 5, mat1 = 2, mat2 = 10, normalForce = 5000, slip = 5, speed = 8, nz = 0.1, slipDirX = 1, slipDirY = 0, slipDirZ = 0 } for k, x in pairs(t) do e[k] = x end return e end
handler(ev({ mat1 = 4 })) handler(ev({ node = 99 })) handler(ev({ normalForce = 100 })) handler(ev({ slip = 0.1 }))
assert(#sent == 0, 'tyres, wheel nodes, light and not-sliding contacts send no hit')
handler(ev({}))
assert(#sent == 1 and sent[1]:find('carSurfaceFx_bodywear.hit(7,5,"wall",10,5000,5.00,8.00,1.000,0.000,0.000)', 1, true), 'a hit: ' .. tostring(sent[1]))
handler(ev({}))
assert(#sent == 1, 'the same node again at once is too soon')
simTime = 2
handler(ev({ node = 6, nz = 0.9 }))
assert(sent[2]:find('"ground"', 1, true), 'a contact on a floor is ground')
W.updateGFX()
local rep = sent[#sent]
assert(#sent == 3 and rep:find('report(7,7,2,1,1,1,1,1,5000,5.0)', 1, true), 'seen 7, hits 2, light 1, still 1, tyre 1, wheel 1, too soon 1: ' .. rep)
W.setConfig(false, false)
assert(handler == nil, 'switched off it unsubscribes')

-- the game side
local drawn = 0
carSurfaceFx_scratch = { hit = function() drawn = drawn + 1 end }
local B = dofile('mod/lua/ge/extensions/carSurfaceFx/bodywear.lua')
B.hit(7, 5, 'wall', 10, 5000, 5, 8, 1, 0, 0)
B.hit(7, 6, 'ground', 10, 5000, 5, 8, 1, 0, 0)
B.hit(7, 6, 'vehicle', 2, 9000, 3, 8, 1, 0, 0)
assert(drawn == 2, 'a wall and a vehicle contact are drawn as scratches, the ground is not (yet): ' .. drawn)
B.report(7, 20, 3, 5, 6, 2, 1, 3, 9000, 5)
local st = B.status()
assert(st:find('seen 20', 1, true) and st:find('hits 3', 1, true) and st:find('wall 1', 1, true) and st:find('light 5', 1, true) and st:find('9000 N', 1, true), 'the status says what was seen: ' .. st)
B.clear()
assert(B.totals().hits == 0, 'clear')
print('carSurfaceFx wear: ok')
