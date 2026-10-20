-- Panel damage: the GE module (carSurfaceFx/paneldamage.lua) against a stand-in for the scratch module and the game
local calls, sat = {}, {}
log = function() end
getAllVehicles = function() return {} end
carSurfaceFx_scratch = {
  dent = function(id, cid, sev, r, maxMarks, light, kind, spread)
    if spread then sat[#sat + 1] = { id = id, cid = cid, sev = sev, spread = spread } return true end         -- the scattered extra marks of a hard hit, counted apart
    calls[#calls + 1] = { id = id, cid = cid, sev = sev, r = r, maxMarks = maxMarks, kind = kind } return true
  end,
  nearestNode = function(id, pos, d) if pos and pos.x == 1 then return 77, 0.1 end return nil end,
  repair = function(id) calls[#calls + 1] = { repair = id } end,
}
local clock = 100                                      -- a fake clock: an impact is collected for 0.8 s, then marked, then the car is quiet for 1.5 s
os.clock = function() return clock end
local P = require('carSurfaceFx/paneldamage')
local function flush() clock = clock + 1.0 P.onUpdate(0.1) clock = clock + 2 end

-- off by default: nothing is drawn
P.hit(5, 10, 8, 20000, 1200, 800, 2, 5)
assert(#calls == 0, 'master off: no dent')
assert(P.damageNode(5, 10, 1000, 'metal') == false and P.damageAt(5, { x = 1 }, 1000) == false, 'master off: the API says no')

P.configure({ enabled = true, metal = true, plastic = true, fibreglass = true, carbon = true, amount = 1, minEnergy = 4, maxMarks = 40 })
P.hit(5, 10, 3, 800, 1200, 800, 2)                    -- no speed change, the node speed capped at 1 m/s: 3 J, under the minimum
flush()
assert(#calls == 0 and P.status().counts.tooSoft >= 1, 'a tap under the minimum leaves nothing')
P.hit(5, 10, 6, 5000, 1200, 800, 2, 5)                   -- the car changed speed by 5 m/s: 75 J
P.hit(5, 10, 6, 5000, 1200, 800, 2, 5)
assert(#calls == 0, 'collected first, drawn when the impact is over')
flush()
assert(#calls == 1 and calls[1].cid == 10 and calls[1].sev > 0.1 and calls[1].r > 0.04 and calls[1].maxMarks == 40, 'a real hit dents its node')
assert(#calls == 1, 'the same node twice in one impact: one mark')
P.hit(5, 11, 6, 5000, 1200, 800, 5, 5)                   -- a glass node
flush()
assert(#calls == 1, 'glass is not a panel')
local harder = {}
P.hit(5, 12, 12, 9000, 1200, 800, 2, 12)
flush()
assert(#calls == 2 and calls[2].sev > calls[1].sev and calls[2].r > calls[1].r, 'a harder hit is deeper and wider')

-- the API
assert(P.damageNode(5, 13, 300, 'metal') == true and #calls == 3, 'damageNode draws')
assert(P.damageNode(5, 13, 300, 'rubber') == false and #calls == 3, 'an unknown kind is refused')
assert(P.damageAt(5, { x = 1, y = 0, z = 0 }, 300, 'metal') == true and calls[4].cid == 77, 'damageAt finds the nearest mapped node')
assert(P.damageAt(5, { x = 9, y = 0, z = 0 }, 300) == false, 'damageAt: no node near, no dent')
assert(P.damageNode(5, 14, 2, 'metal') == false, 'an energy under the minimum draws nothing')
local n0 = #calls
assert(P.damageNode(5, 15, 300, 'carbon') == true and calls[n0 + 1].kind == 'carbon', 'the kind reaches the canvas')
assert(P.damageNode(5, 15, 300, 'plastic') == true and calls[n0 + 2].kind == 'plastic', 'plastic')
assert(P.damageNode(5, 15, 300, 'glass') == false, 'an unknown kind draws nothing')
P.hit(5, 16, 5, 9000, 1200, 800, 3, 5)
flush()
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
P.configure({ enabled = true, metal = true, plastic = true, minEnergy = 4 })
P.probe('log', true)
for i = 1, 14 do P.hit(5, 100 + i, 2 + i * 0.3, 900, 1200, 800, 2, 1 + i * 0.5) end         -- harder and harder (the car's speed changed by 1.5 .. 8 m/s)
for i = 1, 8 do P.hit(5, 200 + i, 1.2, 100, 1200, 800, 2, 0.5) end                    -- then a soft rattle
local st = P.status()
assert(#st.hardest == 10 and #st.latest == 5, 'ten hardest, five latest')
assert(st.hardest[1]:find('change 8.0 m/s', 1, true) and st.latest[#st.latest]:find('change 0.5 m/s', 1, true) and st.hardest[1]:find('node perp 6.2 m/s', 1, true), 'the hardest are not lost to the rattle; the car speed is logged')
-- one impact is hundreds of contacts: only the hardest few are marked, then the rattle is ignored for a while
flush()
calls = {}
P.configure({ enabled = true, metal = true, plastic = true, fibreglass = true, carbon = true, amount = 1, minEnergy = 4, maxMarks = 40 })
for i = 1, 300 do P.hit(7, 300 + i, 2, 400, 1200, 800, 2, 1 + (i % 50) * 0.2) end
assert(#calls == 0, 'nothing is drawn while the impact is still being collected')
clock = clock + 1.0 P.onUpdate(0.1)
assert(#calls >= 1 and #calls <= 16, 'a 300 contact impact leaves a few marks (at most 16): ' .. #calls)
for i = 2, #calls do assert(calls[i].sev <= calls[i - 1].sev + 1e-9, 'the hardest first') end
local n1 = #calls
clock = clock + 0.3
for i = 1, 100 do P.hit(7, 700 + i, 2, 400, 1200, 800, 2, 3) end
clock = clock + 1.0 P.onUpdate(0.1)
assert(#calls == n1 and P.status().counts.quiet > 0, 'the rattle just after is ignored')
clock = clock + 3
P.hit(7, 900, 2, 400, 1200, 800, 2, 3) clock = clock + 1.0 P.onUpdate(0.1)
assert(#calls == n1 + 1, 'a later bump marks again')
-- a car without a paint map yet (a parked car that is hit): its paint map is started and the marks are drawn when it is ready
local mapReady, ensured = false, 0
carSurfaceFx_scratch.hasMap = function(id) return id ~= 9 or mapReady end
carSurfaceFx_scratch.ensureCar = function(id) ensured = ensured + 1 return mapReady end
local dentOrig = carSurfaceFx_scratch.dent
carSurfaceFx_scratch.dent = function(id, cid, ...) if id == 9 and not mapReady then return false end return dentOrig(id, cid, ...) end
calls = {}
clock = clock + 3
P.hit(9, 55, 2, 400, 1200, 800, 2, 6)
clock = clock + 1.0 P.onUpdate(0.1)
assert(#calls == 0 and ensured >= 1, 'no map yet: the car is asked to build one, nothing drawn')
mapReady = true
clock = clock + 0.5 P.onUpdate(0.1)
assert(#calls == 1 and calls[1].id == 9 and calls[1].cid == 55, 'the mark is drawn when the map is ready')
-- the whole impact's speed change, reported by the car a moment before the marking, lifts the contacts that saw only a part of it
calls = {}
clock = clock + 3
for i = 1, 5 do P.hit(11, 800 + i, 2, 200, 1200, 800, 2, 2.4) end            -- each contact saw 2.4 m/s of it: about 15 J
P.impactEnd(11, 5.4)                                                          -- the whole stop took 5.4 m/s: about 75 J
clock = clock + 1.0 P.onUpdate(0.1)
assert(#calls >= 1 and calls[1].sev > 0.5, 'the impact speed change sets the depth: ' .. tostring(calls[1] and calls[1].sev))
-- contacts that each look like a rattle (under the minimum) still mark when the whole impact was a real speed change; with no speed change they leave nothing
calls = {}
clock = clock + 3
for i = 1, 6 do P.hit(12, 900 + i, 2, 150, 1200, 800, 2, 0.3) end
P.impactEnd(12, 3.0)
clock = clock + 1.0 P.onUpdate(0.1)
assert(#calls >= 1, 'a 10 km/h impact whose contacts each read 3 J still marks')
local n2 = #calls
clock = clock + 3
for i = 1, 6 do P.hit(12, 950 + i, 2, 150, 1200, 800, 2, 0.3) end
P.impactEnd(12, 0)
clock = clock + 1.0 P.onUpdate(0.1)
assert(#calls == n2, 'a resting rattle with no speed change leaves nothing')
-- a harder hit scatters more marks round its contacts (energy-weighted), up to the budget
calls, sat = {}, {}
clock = clock + 3
for i = 1, 3 do P.hit(13, 1000 + i, 2, 500, 1200, 800, 2, 10) end         -- 40 km/h class: about 300 J
clock = clock + 1.0 P.onUpdate(0.1)
local soft_n = #calls + #sat
assert(#calls == 3 and #sat >= 8 and soft_n <= 16 and sat[1].spread > 0.2, 'three contacts, the rest of the budget scattered round them: ' .. #calls .. ' + ' .. #sat)
calls, sat = {}, {}
clock = clock + 3
for i = 1, 3 do P.hit(13, 1100 + i, 2, 500, 1200, 800, 2, 3) end          -- 10 km/h class
clock = clock + 1.0 P.onUpdate(0.1)
assert(#calls + #sat < soft_n and #calls + #sat >= 3, 'a gentler hit leaves fewer marks')
print('carSurfaceFx panel damage: ok')
