-- Panel damage: the GE module (carSurfaceFx/paneldamage.lua) against a stand-in for the scratch module and the game
local calls = {}
log = function() end
getAllVehicles = function() return {} end
carSurfaceFx_scratch = {
  dent = function(id, cid, sev, r, maxMarks, light) calls[#calls + 1] = { id = id, cid = cid, sev = sev, r = r, maxMarks = maxMarks } return true end,
  nearestNode = function(id, pos, d) if pos and pos.x == 1 then return 77, 0.1 end return nil end,
  repair = function(id) calls[#calls + 1] = { repair = id } end,
}
local P = require('carSurfaceFx/paneldamage')

-- off by default: nothing is drawn
P.hit(5, 10, 8, 20000, 1200, 800, 2)
assert(#calls == 0, 'master off: no dent')
assert(P.damageNode(5, 10, 1000, 'metal') == false and P.damageAt(5, { x = 1 }, 1000) == false, 'master off: the API says no')

P.configure({ enabled = true, metal = true, amount = 1, minEnergy = 60, maxMarks = 40 })
P.hit(5, 10, 3, 800, 1200, 800, 2)                    -- 0.5 * 6 * 9 = 27 J: under the minimum
assert(#calls == 0 and P.status().counts.tooSoft >= 1, 'a tap under the minimum leaves nothing')
P.hit(5, 10, 6, 5000, 1200, 800, 2)                   -- 108 J
assert(#calls == 1 and calls[1].cid == 10 and calls[1].sev > 0.1 and calls[1].r > 0.04 and calls[1].maxMarks == 40, 'a real hit dents its node')
P.hit(5, 10, 6, 5000, 1200, 800, 2)
assert(#calls == 1, 'the same node again at once: the cooldown holds')
P.hit(5, 11, 6, 5000, 1200, 800, 4)                   -- a rubber node
assert(#calls == 1, 'rubber is not a panel')
local harder = {}
P.hit(5, 12, 12, 9000, 1200, 800, 2)
assert(#calls == 2 and calls[2].sev > calls[1].sev and calls[2].r > calls[1].r, 'a harder hit is deeper and wider')

-- the API
assert(P.damageNode(5, 13, 300, 'metal') == true and #calls == 3, 'damageNode draws')
assert(P.damageNode(5, 13, 300, 'plastic') == false and #calls == 3, 'a kind that is not built yet is refused')
assert(P.damageAt(5, { x = 1, y = 0, z = 0 }, 300, 'metal') == true and calls[4].cid == 77, 'damageAt finds the nearest mapped node')
assert(P.damageAt(5, { x = 9, y = 0, z = 0 }, 300) == false, 'damageAt: no node near, no dent')
assert(P.damageNode(5, 14, 5, 'metal') == false, 'an energy under the minimum draws nothing')
P.clear(5)
assert(calls[#calls].repair == 5, 'clear asks the scratch module to repair the car')

-- the switches
P.configure({ enabled = true, metal = false })
local n = #calls
assert(P.damageNode(5, 20, 500, 'metal') == false and #calls == n, 'the metal switch off: no dents')
P.configure({ enabled = false })
assert(P.damageNode(5, 20, 500, 'metal') == false, 'the master off again')

-- the probe hooks report instead of failing when there is no car
getPlayerVehicle = function() return nil end
assert(P.probe('dent') == 'no player vehicle' and P.probe('log', true) == 'hit log on', 'probe without a car, the log switch')
assert(type(P.status().counts) == 'table', 'status')
print('carSurfaceFx panel damage: ok')
