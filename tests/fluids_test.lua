-- The leaking fluids: the rules (fluidrules.lua), the GE module (fluids.lua) against a mocked game, and the car side (carSurfaceFxFluids.lua) with a mocked car.
local R = require('carSurfaceFx/fluidrules')

-- ---- the rules
local cfg = R.defaults()
local none = R.leaks({})
assert(none.oil == 0 and none.coolant == 0 and none.fuel == 0 and none.exhaust == 0, 'a healthy car leaks nothing')
local flags = R.leaks({ oilPan = true, radiator = true })
assert(flags.oil == 1 and flags.coolant == 1, 'damage flags leak at full without rates')
local rated = R.leaks({ oilPan = true, oilRate = 0.0, coolantRate = 0.15 })
assert(rated.oil == 0 and rated.coolant > 0.55 and rated.coolant < 0.7, 'the engine\'s own rate wins: an empty oil pan leaks no more, half a full leak is ~0.6: ' .. rated.oil .. ' ' .. rated.coolant)
assert(R.leaks({ fuelRate = 0.4, fuelStored = 5 }).fuel > 0.5 and R.leaks({ fuelRate = 0.4, fuelStored = 0 }).fuel == 0, 'a fuel leak stops when the tank is empty')
assert(R.leaks({ running = true, cold = true }).exhaust > 0 and R.leaks({ running = true, cold = false }).exhaust == 0, 'a cold engine that runs condenses in the exhaust')

local n1, c1 = R.drips(1, 0.2, 0)
local total = 0
local carry = 0
for _ = 1, 50 do local n n, carry = R.drips(0.5, 0.2, carry) total = total + n end
assert(n1 == 0 and c1 > 0.7, 'a fifth of a second at full is 0.8 of a drip: ' .. n1 .. ' ' .. c1)
assert(total == 20, 'half a leak for ten seconds is 20 drips: ' .. total)

-- puddles: drips merge and the puddle grows, a stain does not merge, the ring recycles, a puddle dries
local store = R.newStore(10)
local p = R.drip(store, 0, 0, 0, 'oil', 1, cfg, false, 0.3)
local r0 = p.r
for _ = 1, 40 do R.drip(store, 0.1, 0.05, 0, 'oil', 1, cfg, false, 0.3) end
assert(store.count == 1 and p.r > r0 * 2, 'drips under a parked car feed one puddle that grows: ' .. store.count .. ' ' .. r0 .. ' -> ' .. p.r)
for _ = 1, 4000 do R.drip(store, 0.1, 0.05, 0, 'oil', 1, cfg, false, 0.3) end
assert(p.r <= cfg.kinds.oil.size + 1e-9, 'a puddle stops at its size')
R.drip(store, 5, 5, 0, 'oil', 1, cfg, true, 0.5)
R.drip(store, 5.05, 5, 0, 'oil', 1, cfg, true, 0.5)
assert(store.count == 3, 'drip spots of a moving car do not merge: ' .. store.count)
R.drip(store, 0, 0, 0, 'coolant', 1, cfg, false, 0.5)
assert(store.count == 4, 'another fluid is another puddle')
for i = 1, 30 do R.drip(store, 100 + i * 5, 0, 0, 'fuel', 1, cfg, false, 0.5) end
assert(store.count == 10, 'the ring holds max puddles')
R.drip(store, 0, 0, 0, 'lava', 1, cfg, false, 0.5)
assert(store.count == 10, 'an unknown fluid is ignored')

local dry = R.newStore(10)
local c = R.drip(dry, 0, 0, 0, 'coolant', 1, cfg, false, 0.5)
local full = R.alpha(c, cfg)
R.age(dry, cfg.kinds.coolant.life * 0.9, cfg)
assert(R.alpha(c, cfg) < full and R.alpha(c, cfg) > 0, 'a drying puddle thins out')
R.age(dry, cfg.kinds.coolant.life * 0.2, cfg)
assert(c.r == 0 and R.age(dry, 1, cfg) == 0, 'a dried puddle is gone')
local oil = R.drip(dry, 3, 3, 0, 'oil', 1, cfg, false, 0.5)
R.age(dry, 99999, cfg)
assert(oil.r > 0, 'oil stays (life 0)')

-- grip
local g = R.newStore(10)
local pu = R.drip(g, 0, 0, 0, 'oil', 1, cfg, false, 0.5)
pu.r = 1.0
assert(math.abs(R.gripAt(g, 0, 0, cfg) - (1 - cfg.kinds.oil.grip)) < 1e-9, 'in the middle of a puddle the tyre loses the fluid\'s grip')
assert(R.gripAt(g, 5, 5, cfg) == 1, 'far from a puddle full grip')
local edge = R.gripAt(g, 1.0 + cfg.kinds.oil.gripRadius * 0.5, 0, cfg)
assert(edge > 1 - cfg.kinds.oil.grip and edge < 1, 'it fades out past the edge: ' .. edge)
local small = R.newStore(4)
R.drip(small, 0, 0, 0, 'oil', 1, cfg, true, 0.5)
assert(R.gripAt(small, 0, 0, cfg) == 1, 'a drip spot is too small to matter')
local list = R.near(g, 0.5, 0, 14, cfg, 6)
assert(#list == 1 and list[1][3] == 1.0, 'the short list for the car side')
for _, x in ipairs({ { 0, 0 }, { 1.1, 0 }, { 1.2, 0.2 }, { 3, 3 } }) do
  assert(math.abs(R.gripAt(g, x[1], x[2], cfg) - R.gripFromList(list, x[1], x[2])) < 1e-9, 'the list gives the store\'s answer at ' .. x[1] .. ',' .. x[2])
end
assert(R.smooth(1, 0.5, 0.1) < 1 and R.smooth(1, 0.5, 0.1) > 0.3 and R.smooth(0.5, 1, 0.1) < 0.7, 'grip drops fast and comes back slowly')

-- ---- the GE module against a mocked game
local saved = { vec3 = vec3, ColorF = ColorF, Engine = Engine, be = be, core_camera = core_camera, castRayStatic = castRayStatic, getAllVehicles = getAllVehicles, jsonReadFile = jsonReadFile,
  jsonWriteFile = jsonWriteFile, carSurfaceFx_marks = rawget(_G, 'carSurfaceFx_marks') }
local function V(x, y, z) local v = { x = x, y = y, z = z } function v:set(a, b, c) self.x, self.y, self.z = a, b, c end return v end
vec3 = V
ColorF = function(r, g2, b, a) return { r = r, g = g2, b = b, a = a } end
local batches = {}
Engine = { Render = { DynamicDecalMgr = { addDecals = function(pool, n) batches[#batches + 1] = { n = n, tex = pool[1].texture, color = pool[1].color } end } } }
local sent = {}
local pv = { getID = function() return 1 end, getPosition = function() return { x = 0, y = 0, z = 0 } end, getDirectionVector = function() return { x = 1, y = 0, z = 0 } end,
  queueLuaCommand = function(_, cmd) sent[#sent + 1] = cmd end }
be = { getPlayerVehicleID = function() return 1 end, getObjectByID = function(_, id) return pv end, getObjectCount = function() return 1 end, getObject = function() return pv end,
  getPlayerVehicle = function() return pv end }
getAllVehicles = function() return { pv } end
core_camera = { getPosition = function() return { x = 0, y = 0, z = 0 } end }
castRayStatic = function() return 0.6 end                         -- the ground is right under the drip height + 0.6
local files = {}
jsonReadFile = function(f) return files[f] end
jsonWriteFile = function(f, t) files[f] = t end
_G.carSurfaceFx_marks = nil

local F = dofile('mod/lua/ge/extensions/carSurfaceFx/fluids.lua')
F.onExtensionLoaded()
assert(F.get('kinds.oil.size') == cfg.kinds.oil.size and F.get('nothing.here') == nil, 'settings by path')
assert(F.set('gripEnabled', true) and F.get('gripEnabled') == true and not F.set('gripEnabled', 'yes'), 'a setting takes a value of its own type only')
F.set('gripEnabled', false)

-- a parked car with a punctured oil pan: the report comes in five times a second
local t = 0
local realClock = os.clock
os.clock = function() return t end
for i = 1, 100 do
  t = t + 0.2
  F.car(1, 0, 10, 20, 0.4, 10, 22, 0.3, true, false, false, false, 'nil', 'nil', 0, 1, false, true, 1)
end
local st = F.status()
assert(F.count() >= 1 and F.count() <= 4 and st:find('oil=%d') and st:find('leak oil 1.00'), 'a parked leaking car makes a puddle, not a hundred spots: ' .. st)
local biggest = 0
for i = 1, 400 do t = t + 0.2 F.car(1, 0, 10, 20, 0.4, 10, 22, 0.3, true, false, false, false, 'nil', 'nil', 0, 1, false, true, 1) end
assert(F.status():find('oil=%d%(r0%.[4-9]') or F.status():find('oil=%d%(r[1-9]'), 'and it grows while the car stays: ' .. F.status())

-- the same car driving leaves drip spots
F.clear()
for i = 1, 50 do t = t + 0.2 F.car(1, 15, 10 + i, 20, 0.4, 10, 22, 0.3, true, false, false, false, 'nil', 'nil', 0, 1, false, true, 1) end
assert(F.count() >= 20, 'a moving leaking car leaves a trail of drip spots: ' .. F.count())

-- drawing: one batch per fluid and variant, culled by distance
F.clear()
for i = 1, 30 do t = t + 0.2 F.car(1, 0, 10, 20, 0.4, 10, 22, 0.3, true, false, true, false, 'nil', 'nil', 0, 1, false, true, 1) end
batches = {}
core_camera.getPosition = function() return { x = 10, y = 20, z = 0 } end
F.onPreRender(0.016)
assert(#batches >= 2 and batches[1].tex:find('puddle') or batches[1].tex:find('drop'), 'oil and coolant are drawn in their own batches: ' .. #batches)
core_camera.getPosition = function() return { x = 5000, y = 0, z = 0 } end
batches = {}
F.onPreRender(0.016)
assert(#batches == 0, 'far from the camera nothing is drawn')
core_camera.getPosition = function() return { x = 10, y = 20, z = 0 } end

-- the marks seam is used when the marks module is there
local seamCalls = 0
_G.carSurfaceFx_marks = { drawBatch = function(pool, n) seamCalls = seamCalls + 1 end }
batches = {}
F.onPreRender(0.016)
assert(seamCalls >= 2 and #batches == 0, 'the decals go through marks.drawBatch (the lighting seam)')
_G.carSurfaceFx_marks = nil

-- the grip: off, nothing is sent but an empty list; on, the puddles near the car go to it
F.puddleAhead('oil', 3, 1.2)
sent = {}
F.onUpdate(0.3)
assert(sent[1] and sent[1]:find('setPuddles%({%}%)'), 'grip off: an empty list: ' .. tostring(sent[1]))
F.set('gripEnabled', true)
sent = {}
F.onUpdate(0.3)
local pushed
for _, cmd in ipairs(sent) do if cmd:find('setPuddles%({{') then pushed = cmd end end
assert(pushed, 'grip on: the puddle ahead is sent to the car: ' .. tostring(sent[#sent]))
assert(F.gripAt(3, 0) < 1, 'the rules give less than full grip in it')
F.onExtensionUnloaded()

-- ---- the car side with a mocked car
local appliedCalls = {}
obj = { getPosition = function() return { x = 3, y = 0, z = 0 } end, getVelocity = function() return { x = 0, y = 0, z = 0 } end, getId = function() return 1 end,
  getAbsNodePosition = function(_, n) return ({ [1] = { x = 2.5, y = 0.5, z = 0.3 }, [2] = { x = 2.5, y = 0.5, z = 0.3 }, [3] = { x = 8, y = 8, z = 0.3 }, [4] = { x = 8, y = 8, z = 0.3 } })[n] end,
  setNodeFrictionSlidingCoefs = function(_, nid, a, b) appliedCalls[#appliedCalls + 1] = { nid, a, b } end, queueGameEngineLua = function(_, cmd) sent[#sent + 1] = cmd end }
wheels = { wheels = { [0] = { node1 = 1, node2 = 2, treadNodes = { 10, 11 } }, [1] = { node1 = 3, node2 = 4, treadNodes = { 12 }, isTireDeflated = false } } }
v = { data = { nodes = { [10] = { frictionCoef = 1.0, slidingFrictionCoef = 0.9 }, [11] = { frictionCoef = 1.0 }, [12] = { frictionCoef = 1.2 } } } }
damageTracker = { getDamage = function(_, name) return name == 'oilpanLeak' end }
energyStorage = { getStorages = function() return {} end }
electrics = { values = { rpm = 800, watertemp = 90 } }
powertrain = { getDevice = function() return { engineNodeID = 1, thermals = { debugData = { engineThermalData = { oilLeakRateOverall = 0.1, coolantLeakRateOverall = 0 } } } } end }
extensions = extensions or {}
local C = dofile('mod/lua/vehicle/extensions/carSurfaceFxFluids.lua')
C.setConfig(true, false, true)
sent = {}
C.updateGFX(0.25)
assert(sent[1] and sent[1]:find('carSurfaceFx_fluids.car%(1,') and sent[1]:find('true,false,false,false,0.1,0,'), 'the car reports its damage and the engine\'s own leak rates: ' .. tostring(sent[1]))
C.setPuddles({ { 2.5, 0.5, 1.0, 0.55, 0.25 } })
for _ = 1, 20 do C.updateGFX(0.1) end
local m10
for _, c2 in ipairs(appliedCalls) do if c2[1] == 10 then m10 = c2 end end
assert(m10 and math.abs(m10[2] - 0.45) < 0.01 and math.abs(m10[3] - 0.45 * 0.9 / 1.0 * 1.0) < 0.2, 'the tyre in the puddle has its friction scaled by the grip multiplier: ' .. tostring(m10 and m10[2]))
local other
for _, c2 in ipairs(appliedCalls) do if c2[1] == 12 then other = c2 end end
assert(other == nil, 'the tyre outside the puddle is left alone')
assert(math.abs(C.gripAt(2.5, 0.5) - R.gripFromList({ { 2.5, 0.5, 1.0, 0.55, 0.25 } }, 2.5, 0.5)) < 1e-9, 'the car side and the rules agree')
wheels.wheels[0].isTireDeflated = true
appliedCalls = {}
for _ = 1, 10 do C.updateGFX(0.1) end
assert(#appliedCalls == 0, 'a deflated tyre is not touched')
wheels.wheels[0].isTireDeflated = false
C.onReset()
local back
for _, c2 in ipairs(appliedCalls) do if c2[1] == 10 then back = c2 end end
assert(back and back[2] == 1.0, 'a reset gives the tyres their full grip at once')

-- restore the globals
os.clock = realClock
vec3, ColorF, Engine, be, core_camera, castRayStatic, getAllVehicles, jsonReadFile, jsonWriteFile = saved.vec3, saved.ColorF, saved.Engine, saved.be, saved.core_camera, saved.castRayStatic,
  saved.getAllVehicles, saved.jsonReadFile, saved.jsonWriteFile
_G.carSurfaceFx_marks = saved.carSurfaceFx_marks
obj, wheels, v, damageTracker, energyStorage, electrics, powertrain = nil, nil, nil, nil, nil, nil, nil
print('carSurfaceFx fluids: ok')
