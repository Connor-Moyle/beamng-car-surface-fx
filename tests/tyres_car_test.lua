-- The car side of the tyres (carSurfaceFxTyres.lua) with a mocked car: energy from the wheel, wear, grip writes, one writer with the fluids, reset, deflation.
local writes = {}
local sent = {}
local tread = {}
for j = 1, 32 do tread[j] = 100 + j end
local nodes = {}
for _, cid in ipairs(tread) do nodes[cid] = { frictionCoef = 1.0, slidingFrictionCoef = 0.9 } end
local wd = { treadNodes = tread, radius = 0.305, downForce = 4000, lastSlip = 8, lastTreadContactNode = 105, wheelSpeed = 20, pressureGroupId = 1, isTireDeflated = false }
wheels = { wheels = { [0] = wd } }
v = { data = { nodes = nodes } }
obj = { setNodeFrictionSlidingCoefs = function(_, cid, a, b) writes[#writes + 1] = { cid, a, b } end, getEnvTemperature = function() return 293.15 end,
  getGroupPressure = function() return 200000 end, queueGameEngineLua = function(_, c) sent[#sent + 1] = c end, getId = function() return 7 end }
log = function() end
local T = dofile('mod/lua/vehicle/extensions/carSurfaceFxTyres.lua')

T.updateGFX(0.01)
assert(not T.active(), 'off until the game side switches it on')
T.setConfig({ enabled = true, wearRate = 200 })
for _ = 1, 20 do T.updateGFX(0.01) end
assert(T.active(), 'built on the first frame it is on')
local lastW = {}
for _, w in ipairs(writes) do lastW[w[1]] = w end
-- 8 m/s slip at 4000 N for 0.2 s on one contact node wore its slot and its lane mate; the rest is untouched
local blob = T.snapshot()[0]
assert(blob.h[5] < 8.0 and blob.h[6] < 8.0, 'the contact node and its lane mate wore: ' .. tostring(blob.h[5]))
assert(blob.h[5] == blob.h[6] and blob.h[1] == 8.0 and blob.h[20] == 8.0, 'only that sector wore')
assert(lastW[105] and lastW[105][2] < 1.0 and math.abs(lastW[105][3] / lastW[105][2] - 0.9) < 1e-6, 'the worn node has less grip, written from the stock 1.0 / 0.9')
assert(lastW[101] == nil or lastW[101][2] <= 1.001, 'a node nothing touched is not weakened')

-- a deflated tyre is the game's: nothing is written
writes = {}
wd.isTireDeflated = true
for _ = 1, 20 do T.updateGFX(0.01) end
assert(#writes == 0, 'a deflated tyre is not touched')
wd.isTireDeflated = false

-- one writer: the fluids' multiplier is a factor on top of the tyre's
local before = {}
T.setExternal('fluids', 0, 0.5)
local w105
for _, w in ipairs(writes) do if w[1] == 105 then w105 = w end end
assert(w105 and w105[2] < 0.6, 'the fluids factor goes through the tyre module: ' .. tostring(w105 and w105[2]))
local F = dofile('mod/lua/vehicle/extensions/carSurfaceFxFluids.lua')
local got
wd.node1 = 1
obj.getAbsNodePosition = function() return { x = 0, y = 0, z = 0 } end
obj.getPosition = function() return { x = 0, y = 0, z = 0 } end
obj.getVelocity = function() return { x = 0, y = 0, z = 0 } end
_G.carSurfaceFxTyres = { active = function() return true end, setExternal = function(kind, wi, m) got = { kind, wi, m } end }
writes = {}
F.setConfig(false, false, true)
F.setPuddles({ { 0, 0, 1, 0.5, 0.2 } })
for _ = 1, 20 do F.updateGFX(0.1) end
assert(got and got[1] == 'fluids' and got[2] == 0 and got[3] < 1, 'with the tyre module active the fluids hand over their factor')
assert(#writes == 0, 'and write nothing themselves')
_G.carSurfaceFxTyres = nil

-- a reset gives new tyres: the wear and the blown state are gone
T.setConfig({ enabled = true, wearRate = 400 })
wd.lastSlip, wd.downForce = 30, 8000
for _ = 1, 100 do T.updateGFX(0.01) end
assert(T.snapshot()[0].h[5] < 8.0, 'worn before the reset')
T.onReset()
assert(T.snapshot()[0].h[5] == 8.0 and not T.snapshot()[0].blown, 'a reset gives new tyres')
wd.lastSlip = 8
T.setConfig({ wearRate = 1 })

-- a reset: the engine restores stock friction, ours comes back two frames later
writes = {}
T.onReset()
T.updateGFX(0.01)
assert(#writes == 0, 'nothing on the first frame after a reset (the engine is still restoring its own values)')
T.updateGFX(0.01)
assert(#writes >= 32, 'every tread node is written again on the second frame: ' .. #writes)

-- a restore puts the stock friction back; switching off does it
writes = {}
T.setConfig({ enabled = false })
local stock = 0
for _, w in ipairs(writes) do if w[2] == 1.0 and w[3] == 0.9 then stock = stock + 1 end end
assert(stock == 32, 'switched off: stock friction everywhere: ' .. stock)

-- a saved state is restored onto a fresh car
T.setConfig({ enabled = true })
T.repair()
assert(T.snapshot()[0].h[5] == 8.0, 'a garage tyre change gives fresh tread')
T.restoreSnapshot({ [0] = blob })
assert(T.snapshot()[0].h[5] == blob.h[5], 'the saved wear comes back')

-- the stock class from the jbeam numbers, and a fitted compound
assert(T.classify({ noLoadCoef = 1.35, treadCoef = 0.7, radius = 0.305 }) == 'road', 'a standard tyre is a road tyre')
assert(T.classify({ noLoadCoef = 2.07, treadCoef = 0, radius = 0.31 }) == 'semislick', 'a race tyre is a semi-slick')
assert(T.classify({ noLoadCoef = 1.3, treadCoef = 1.0, radius = 0.42 }) == 'offroad', 'a big blocky tyre is an off-road tyre')
T.setCompound('slick')
for _ = 1, 3 do T.updateGFX(0.01) end
assert(T.snapshot()[0].compound == 'slick', 'fitted: the tyres are rebuilt as slicks')
T.setCompound(nil)
T.updateGFX(0.01)
assert(T.snapshot()[0].compound == 'road', 'back to the stock class')

-- the flat-spot shake: nothing on a round tyre; after a lock-up (energy on one sector) the rate follows the wheel and the force the depth
T.setConfig({ enabled = true, wearRate = 400 })
local hz0, f0 = T.shake(0)
assert(hz0 == 0 and f0 == 0, 'a round tyre does not shake')
wd.lastSlip, wd.wheelSpeed, wd.angularVelocity = 30, 0, 0
for _ = 1, 300 do T.updateGFX(0.01) end
wd.lastSlip, wd.wheelSpeed, wd.angularVelocity = 0, 20, 20 / 0.305
local hz, f = T.shake(0)
assert(hz > 8 and hz < 12 and f > 0, 'a flat spot shakes once a revolution (about ' .. 20 / (2 * math.pi * 0.305) .. ' Hz): ' .. hz .. ', ' .. f)

-- the ground and the water come from the wheel's own contact material and the water check
T.setSurfaces({ ['10'] = 'asphalt', ['11'] = 'asphalt', ['13'] = 'gravel' })      -- (what the game side sends from the ground models)
obj.inWater = function() return false end
T.setConfig({ enabled = true })
T.setExternal('fluids', 0, 1)
T.repair()
writes = {}
wd.contactMaterialID1, wd.contactMaterialID2, wd.node1, wd.lastSlip = 4, 13, 1, 0
for _ = 1, 20 do T.updateGFX(0.01) end
local g101
for _, w in ipairs(writes) do if w[1] == 101 then g101 = w end end
assert(g101 and g101[2] < 0.95 * 1.0 and g101[2] > 0.5, 'on gravel a road tyre has less grip than the stock friction: ' .. tostring(g101 and g101[2]))
writes = {}
wd.contactMaterialID1, wd.contactMaterialID2 = 4, 11
T.setConfig({ wearRate = 1 })
for _ = 1, 20 do T.updateGFX(0.01) end
obj.inWater = function() return true end
for _ = 1, 20 do T.updateGFX(0.01) end
assert(T.water():find('own 0.70', 1, true), 'a hub under water counts as deep: ' .. T.water())
obj.inWater = function(_, cid) return cid == 105 end          -- only the contact patch (the contact node of the mock is 105): a flooded road
for _ = 1, 20 do T.updateGFX(0.01) end
assert(T.water():find('own 0.30', 1, true), 'a covered contact patch counts as shallow: ' .. T.water())
obj.inWater = function() return false end
for _ = 1, 20 do T.updateGFX(0.01) end
assert(T.water():find('own 0.00', 1, true), 'dry: none')
obj.inWater = function() return true end
assert(#sent > 0, 'runs with ground and water readings')
obj.inWater = nil
wd.contactMaterialID1, wd.contactMaterialID2 = nil, nil

-- the state goes to the game side
sent = {}
for _ = 1, 60 do T.updateGFX(0.01) end
assert(sent[1] and sent[1]:find('carSurfaceFx_tyres.state%(7,'), 'the state goes to the game side: ' .. tostring(sent[1]))

print('carSurfaceFx tyres (car side): ok')

-- the ground under the wheel and the water: surfaces by material id, debris events, the spread to the car
T.setConfig({ enabled = true })
T.repair()
T.setSurfaces({ ['9'] = 'dirt', ['3'] = 'asphalt' })
wd.contactMaterialID1, wd.contactMaterialID2 = 4, 9
for _ = 1, 20 do T.updateGFX(0.01) end
assert(T.status():find('enabled true'), 'still running')
local sentBefore = #sent
T.setConfig({ wearRate = 5000 })
wd.lastSlip, wd.downForce = 20, 8000
for _ = 1, 300 do T.updateGFX(0.01) end
local sawDebris
for k = sentBefore + 1, #sent do if sent[k]:find('"debris"', 1, true) then sawDebris = true end end
assert(sawDebris, 'worn rubber goes to the game side as debris events')
-- a tyre fire goes to the game's own fire system as one flammable tread node, and is taken out again
fire = { debugData = { flammableNodes = {} }, igniteNode = function(cid, temp) fire.lit = { cid, temp } end }
T.setConfig({ enabled = true })
T.repair()
for _ = 1, 3 do T.updateGFX(0.01) end
assert(T.lightTyre(0) and fire.lit and fire.lit[1] == 101 and fire.debugData.flammableNodes[101].burnRate >= 1, 'the tread node is given to the game fire with a real burn rate')
local burning = fire.debugData.flammableNodes[101]
burning.intensity, burning.temperature = 1, 900
assert(T.putOut(0) and fire.debugData.flammableNodes[101] == nil, 'and taken out again')
assert(burning.chemEnergy == 0 and burning.intensity == 0 and burning.temperature == 20, 'the node itself is stopped: the game keeps it in its hot list and it would burn on (probe f10)')
assert(not T.putOut(0), 'nothing to put out twice')
fire = nil
assert(not T.lightTyre(0), 'no fire module: nothing happens')
-- a compound for one axle, and a part-worn tread
wd.name = 'FL'
T.setConfig({ enabled = true })
T.setCompound(nil)
T.setCompound('slick', 'front')
assert(T.snapshot()[0].compound == 'slick', 'the front axle got slicks')
T.setCompound('fullwet', 'rear')
assert(T.snapshot()[0].compound == 'slick', 'and the rear set leaves it alone')
T.setTread(0.5)
local half = T.snapshot()[0]
assert(math.abs(half.h[5] - 1.5) < 0.01 and math.abs(half.h[20] - 1.5) < 0.01 and not half.blown, 'a half-worn tread: 1.5 mm of a slick 3.0 everywhere')
T.setCompound(nil)
wd.name = nil
-- two wheels, one burning: a reset clears both
local tread2 = {}
for j = 1, 32 do tread2[j] = 200 + j nodes[200 + j] = { frictionCoef = 1.0, slidingFrictionCoef = 0.9 } end
local wd2 = { treadNodes = tread2, radius = 0.305, downForce = 4000, lastSlip = 0, lastTreadContactNode = 205, wheelSpeed = 20, name = 'FR' }
wheels.wheels[1] = wd2
T.setConfig({ enabled = true, heatRate = 6, wearRate = 1 })
T.setCompound(nil)
for _ = 1, 3 do T.updateGFX(0.01) end
wd.lastSlip, wd2.lastSlip = 0, 30
local burning
for _ = 1, 2000 do T.updateGFX(0.01) end
local st = T.status()
T.onReset()
for _ = 1, 5 do T.updateGFX(0.01) end
local after = T.snapshot()
assert(after[1].h[5] == 8.0 and after[0].h[5] == 8.0 and not after[1].blown, 'a reset gives new tyres on every wheel: ' .. tostring(after[1].h[5]))
wheels.wheels[1] = nil
T.setCompound(nil)
T.setConfig({ heatRate = 1 })
-- locked sliding wears at the low rate, wheelspin spinWear times faster
local function wearOf(wheelSpeed)
  T.setConfig({ enabled = true, wearRate = 50 })
  T.repair()
  wd.lastSlip, wd.wheelSpeed, wd.downForce, wd.lastTreadContactNode = 10, wheelSpeed, 4000, 105
  for _ = 1, 50 do T.updateGFX(0.01) end
  return 8 - T.snapshot()[0].h[5]
end
local locked, spinning = wearOf(0), wearOf(20)
assert(locked > 0 and spinning / locked > 2.5 and spinning / locked < 5, 'a locked wheel wears less than a spinning one: ' .. locked .. ' vs ' .. spinning)
T.setConfig({ wearRate = 1 })
-- grip() reads the factor written on the tyres: a slick in the rain far below a rain tyre, and above a road tyre in the dry
local function gripNow(name, wet)
  T.setConfig({ enabled = true })
  T.setCompound(name)
  T.setEnv({ wet = wet, water = 0 })
  wd.lastSlip, wd.wheelSpeed, wd.downForce = 0, 20, 4000
  for _ = 1, 30 do T.updateGFX(0.01) end
  return tonumber(T.grip():match('([%d.]+)$'))
end
local gDry, gSlickWet, gRoadWet, gRainWet = gripNow('slick', 0), gripNow('slick', 1), gripNow('road', 1), gripNow('fullwet', 1)
assert(gSlickWet < 0.7 * gRoadWet and gRoadWet < gRainWet, 'in heavy rain: slick ' .. gSlickWet .. ' < 0.7 x road ' .. gRoadWet .. ' < full wet ' .. gRainWet)
assert(gDry > gSlickWet, 'and the slick is better dry than wet: ' .. gDry .. ' vs ' .. gSlickWet)
T.setEnv({ wet = 0, water = 0 })
T.setCompound(nil)
-- belts (no tread left) sliding throw sparks (particle 1) at the contact patch; the readouts never go below 0
T.setConfig({ enabled = true })
local sparks = 0
obj.addParticleByNodesRelative = function(_, _, _, _, id) if id == 1 then sparks = sparks + 1 end end
wd.lastSlip, wd.downForce, wd.isTireDeflated = 8, 4000, false
T.updateGFX(0.01)
T.setTread(0, 0)
for _ = 1, 12 do T.updateGFX(0.1) end
assert(sparks > 0, 'sparks from belts that slip: ' .. sparks .. ' ' .. T.status() .. ' active ' .. tostring(T.active()))
local before = sparks
T.setTread(1, 0)
for _ = 1, 12 do T.updateGFX(0.1) end
assert(sparks == before, 'a tyre with tread throws none')
T.setTread(0, 0)
for _ = 1, 3 do T.updateGFX(0.1) end
assert(not T.status():find('worst tread -', 1, true), 'worst tread is never shown below 0: ' .. T.status())
-- standing water (the environment's depth, e.g. a flooded road) above the aquaplaning speed takes grip away, and gives it back when the water is gone
T.setConfig({ enabled = true, wearRate = 0 })
wd.isTireDeflated, wd.wheelSpeed, wd.lastSlip = false, 35, 0
wd.contactMaterialID1, wd.contactMaterialID2 = 4, 10
obj.inWater = function() return false end
T.setEnv({ wet = 0, water = 0 })
T.repair()
for _ = 1, 30 do T.updateGFX(0.1) end
local gDryAq = tonumber(T.grip():match('(%d%.%d+)$'))
T.setEnv({ wet = 0, water = 0.6 })
for _ = 1, 30 do T.updateGFX(0.1) end
local gWaterAq = tonumber(T.grip():match('(%d%.%d+)$'))
assert(gWaterAq < 0.8 * gDryAq, 'at 35 m/s in standing water the road tyre loses grip: ' .. gDryAq .. ' -> ' .. gWaterAq)
wd.wheelSpeed = 8
for _ = 1, 30 do T.updateGFX(0.1) end
assert(tonumber(T.grip():match('(%d%.%d+)$')) > 0.9 * gDryAq * 0.8, 'slowly there is no aquaplaning')
T.setEnv({ wet = 0, water = 0 })
wd.wheelSpeed = 35
for _ = 1, 30 do T.updateGFX(0.1) end
assert(tonumber(T.grip():match('(%d%.%d+)$')) > gWaterAq, 'and the grip comes back when the water is gone')
-- a puddle depth told per wheel by Street Legal does the same, and fades when it is not renewed
assert(T.active(), 'the module says it owns the tyres')
local told = 0
for wi = 0, 8 do if T.setWheelWater(wi, 0.6) then told = told + 1 end end
assert(told > 0, 'a wheel took the puddle depth')
for _ = 1, 3 do T.updateGFX(0.1) end
assert(tonumber(T.grip():match('(%d%.%d+)$')) < 0.8 * gDryAq, 'a puddle under the wheel takes grip away: ' .. T.grip())
for _ = 1, 30 do T.updateGFX(0.1) end
assert(tonumber(T.grip():match('(%d%.%d+)$')) > 0.95 * gDryAq, 'the puddle fades when it is not renewed')
-- a full wet tyre in standing water: the readout is there, and it holds up better than the road tyre
T.setCompound('fullwet')
T.repair()
T.setEnv({ wet = 0, water = 0.6 })
for _ = 1, 30 do T.updateGFX(0.1) end
assert(T.gripWhy():find('surface', 1, true) and T.gripWhy():find('ext 1.00', 1, true), 'gripWhy lists the inputs: ' .. T.gripWhy())
assert(T.grip() ~= '' and T.grip():find('fullwet', 1, true), 'grip() is not empty on a fullwet tyre in water: ' .. T.grip())
assert(tonumber(T.grip():match('(%d%.%d+)$')) > gWaterAq, 'fullwet floats later than the road tyre: ' .. T.grip())
T.setEnv({ wet = 0, water = 0 })
-- right after a compound change (the tyres are rebuilt on the next frame) the readouts still answer
T.setCompound('fullwet')
assert(T.grip() ~= '' and T.water() ~= '' and T.status():find('tyres 1', 1, true), 'readouts right after setCompound: [' .. T.grip() .. '] [' .. T.water() .. '] ' .. T.status())
T.setCompound(nil)
-- the burnout test hook heats the tyre and wears it, and stops by itself; cornering wears slower than wheelspin
T.setCompound('road') T.repair() T.updateGFX(0.1)
wd.isTireDeflated, wd.wheelSpeed, wd.lastSlip, wd.downForce = false, 0, 0, 4000
T.setEnv({ wet = 0, water = 0 })
local fed = 0
for wi = 0, 8 do if T.testBurn(wi, 100000, 100) then fed = fed + 1 end end
assert(fed > 0, 'the hook found a wheel')
local ts0 = tonumber(T.status():match('hottest (%d+)'))
for _ = 1, 100 do T.updateGFX(0.1) end
assert(tonumber(T.status():match('hottest (%d+)')) > ts0 + 100, 'a burnout of 100 kW makes the tyre hot: ' .. T.status())
for wi = 0, 8 do T.testBurn(wi, 0) end
T.setConfig({ enabled = true, wearRate = 3 })
local function wearOf(ws, slip)
  T.repair()
  wd.wheelSpeed, wd.lastSlip = ws, slip
  for _ = 1, 100 do T.updateGFX(0.1) end
  return 8 - tonumber(T.status():match('worst tread ([%d%.]+)'))
end
local wSpin, wCorner = wearOf(8, 8), wearOf(15, 3)
assert(wSpin > 0 and wCorner >= 0 and wCorner / 3 < wSpin / 8, 'wheelspin wears more per slip than cornering: ' .. wSpin .. ' vs ' .. wCorner)
wheels, v, obj, log = nil, nil, nil, nil
