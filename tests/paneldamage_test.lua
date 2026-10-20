-- Panel damage: the GE module (carSurfaceFx/paneldamage.lua) against a stand-in for the scratch module and the game
local calls = {}
log = function() end
getAllVehicles = function() return {} end
carSurfaceFx_scratch = {
  dent = function(id, cid, sev, r, maxMarks, light, kind) calls[#calls + 1] = { id = id, cid = cid, sev = sev, r = r, maxMarks = maxMarks, kind = kind } return true end,
  nearestNode = function(id, pos, d) if pos and pos.x == 1 then return 77, 0.1 end return nil end,
  repair = function(id) calls[#calls + 1] = { repair = id } end,
}
local P = require('carSurfaceFx/paneldamage')

-- off by default: nothing is drawn
P.hit(5, 10, 8, 20000, 1200, 800, 2, 5)
assert(#calls == 0, 'master off: no dent')
assert(P.damageNode(5, 10, 1000, 'metal') == false and P.damageAt(5, { x = 1 }, 1000) == false, 'master off: the API says no')

P.configure({ enabled = true, metal = true, plastic = true, fibreglass = true, carbon = true, amount = 1, minEnergy = 60, maxMarks = 40 })
P.hit(5, 10, 3, 800, 1200, 800, 2)                    -- 0.5 * 6 * 9 = 27 J: under the minimum
assert(#calls == 0 and P.status().counts.tooSoft >= 1, 'a tap under the minimum leaves nothing')
P.hit(5, 10, 6, 5000, 1200, 800, 2, 5)                   -- the car changed speed by 5 m/s: 75 J
assert(#calls == 1 and calls[1].cid == 10 and calls[1].sev > 0.1 and calls[1].r > 0.04 and calls[1].maxMarks == 40, 'a real hit dents its node')
P.hit(5, 10, 6, 5000, 1200, 800, 2, 5)
assert(#calls == 1, 'the same node again at once: the cooldown holds')
P.hit(5, 11, 6, 5000, 1200, 800, 5, 5)                   -- a glass node
assert(#calls == 1, 'glass is not a panel')
local harder = {}
P.hit(5, 12, 12, 9000, 1200, 800, 2, 12)
assert(#calls == 2 and calls[2].sev > calls[1].sev and calls[2].r > calls[1].r, 'a harder hit is deeper and wider')

-- the API
assert(P.damageNode(5, 13, 300, 'metal') == true and #calls == 3, 'damageNode draws')
assert(P.damageNode(5, 13, 300, 'rubber') == false and #calls == 3, 'an unknown kind is refused')
assert(P.damageAt(5, { x = 1, y = 0, z = 0 }, 300, 'metal') == true and calls[4].cid == 77, 'damageAt finds the nearest mapped node')
assert(P.damageAt(5, { x = 9, y = 0, z = 0 }, 300) == false, 'damageAt: no node near, no dent')
assert(P.damageNode(5, 14, 5, 'metal') == false, 'an energy under the minimum draws nothing')
local n0 = #calls
assert(P.damageNode(5, 15, 300, 'carbon') == true and calls[n0 + 1].kind == 'carbon', 'the kind reaches the canvas')
assert(P.damageNode(5, 15, 300, 'plastic') == true and calls[n0 + 2].kind == 'plastic', 'plastic')
assert(P.damageNode(5, 15, 300, 'glass') == false, 'an unknown kind draws nothing')
P.hit(5, 16, 5, 9000, 1200, 800, 3, 5)
assert(calls[#calls].kind == 'plastic', 'a plastic node takes a plastic mark')
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
-- the log keeps the hardest hits apart from the latest ones
P.configure({ enabled = true, metal = true, plastic = true, minEnergy = 60 })
P.probe('log', true)
for i = 1, 14 do P.hit(5, 100 + i, 2 + i * 0.3, 900, 1200, 800, 2, 1 + i * 0.5) end         -- harder and harder (the car's speed changed by 1.5 .. 8 m/s)
for i = 1, 8 do P.hit(5, 200 + i, 1.2, 100, 1200, 800, 2, 0.5) end                    -- then a soft rattle
local st = P.status()
assert(#st.hardest == 10 and #st.latest == 5, 'ten hardest, five latest')
assert(st.hardest[1]:find('change 8.0 m/s', 1, true) and st.latest[#st.latest]:find('change 0.5 m/s', 1, true) and st.hardest[1]:find('node perp 6.2 m/s', 1, true), 'the hardest are not lost to the rattle; the car speed is logged')
print('carSurfaceFx panel damage: ok')
