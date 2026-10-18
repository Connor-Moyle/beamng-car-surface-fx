-- Car Surface FX, vehicle side: leaking fluids and the grip they take. Five times a second this reads what the car really has: the engine's own oil and coolant leak rates (kg/s) and
-- the damage flags (oil pan, oil cooler, radiator, overheating), the fuel tanks' leak rate, the engine temperature and the first exhaust tip, and sends it to the GE side
-- (carSurfaceFx_fluids.car), which decides what drips where. The puddles near the car come back (setPuddles) and each tyre scales its own friction by the puddle it stands in
-- (obj:setNodeFrictionSlidingCoefs, the call the game's own tyre deflation uses), smoothly, and never on a deflated tyre.
local M = {}
local abs, min, max, sqrt = math.abs, math.min, math.max, math.sqrt

local INTERVAL = 0.2                       -- seconds between reports
local APPLY_EPS = 0.01                     -- not worth calling the setter for a change this small
local RISE, FALL = 6.0, 1.2                -- 1/s: grip drops fast in a puddle, comes back slower

local emit = false                         -- the GE side switches it on for the cars that leak
local drops, dropWidth, dropCount = true, 0.06, 2   -- the falling drops: the game's own fluid-drop particles from the leak point
local DROP_PARTICLE = { oil = 36, coolant = 48, fuel = 50, exhaust = 50 }   -- BNGP_<n>, kept equal to the GE side's fluidrules.DROP_PARTICLE by the test
local exhaustOn = false
local gripOn = false
local puddles = {}                         -- { {x, y, r, grip, radius}, ... } near the car (from GE)
local forced = {}                          -- debug: kinds forced to leak
local timer = 0
local engine, tipNode                      -- cached
local looked = false
local wheelTread, built = nil, false       -- wi -> { {nid, fc, sfc}, ... } with the baseline friction
local mult = {}                            -- wi -> the multiplier now
local applied = {}                         -- wi -> the multiplier last pushed to the nodes
local lowest = 1

local function dmg(name)
  local v = false
  pcall(function() v = damageTracker and damageTracker.getDamage('engine', name) or false end)
  return v and true or false
end

local function findEngine()
  looked = true
  pcall(function()
    if powertrain and powertrain.getDevice then
      engine = powertrain.getDevice('mainEngine')
      local ends = engine and engine.thermals and engine.thermals.exhaustEndNodes
      if ends and ends[1] and ends[1].finish then tipNode = ends[1].finish end
    end
  end)
end

local function engineData()
  local d
  pcall(function() d = engine and engine.thermals and engine.thermals.debugData and engine.thermals.debugData.engineThermalData end)
  return d
end

local function fuelLeak()
  local rate, stored = 0, 1
  pcall(function()
    for _, s in pairs(energyStorage.getStorages()) do
      if (s.currentLeakRate or 0) > 0 and (s.storedEnergy or 0) > 0 then rate = rate + s.currentLeakRate stored = s.storedEnergy end
    end
  end)
  return rate, stored
end

-- the grip multiplier at a point from the puddles (the same maths as fluidrules.gripFromList: tests/fluids_test.lua holds the two together)
local function gripAt(x, y)
  local m = 1
  for i = 1, #puddles do
    local e = puddles[i]
    local dx, dy = e[1] - x, e[2] - y
    local d = sqrt(dx * dx + dy * dy)
    local r, grip, gr = e[3], e[4], e[5]
    if d < r + gr then
      local f = d <= r and 1 or 1 - (d - r) / max(0.01, gr)
      local k = 1 - grip * f
      if k < m then m = k end
    end
  end
  return m
end
M.gripAt = gripAt

local function buildTread()
  if built then return end
  if not wheels or not wheels.wheels or not v or not v.data or not v.data.nodes or not next(wheels.wheels) then return end
  wheelTread = {}
  for wi, wd in pairs(wheels.wheels) do
    if wd.treadNodes then
      local list = {}
      for _, nid in pairs(wd.treadNodes) do
        local nd = v.data.nodes[nid]
        local fc = nd and nd.frictionCoef
        if fc then list[#list + 1] = { nid = nid, fc = fc, sfc = nd.slidingFrictionCoef or fc } end
      end
      if #list > 0 then wheelTread[wi] = list end
    end
  end
  built = true
end

local function wheelContact(wd)
  local p1 = obj:getAbsNodePosition(wd.node1)
  local x, y = p1.x, p1.y
  if wd.node2 then local p2 = obj:getAbsNodePosition(wd.node2) x, y = (x + p2.x) * 0.5, (y + p2.y) * 0.5 end
  return x, y
end

local function applyWheel(wi, m)
  local list = wheelTread and wheelTread[wi]
  if not list then return end
  for _, e in ipairs(list) do
    pcall(function() obj:setNodeFrictionSlidingCoefs(e.nid, e.fc * m, e.sfc * m) end)
  end
  applied[wi] = m
end

-- every frame while a puddle is near or a tyre is still below full grip
local function gripFrame(dt)
  if not gripOn and lowest >= 0.999 then return end
  buildTread()
  if not wheelTread then return end
  lowest = 1
  for wi, wd in pairs(wheels.wheels) do
    if wheelTread[wi] then
      local cur = mult[wi] or 1
      local target = 1
      if gripOn and #puddles > 0 and not wd.isTireDeflated then
        local x, y = wheelContact(wd)
        target = gripAt(x, y)
      end
      local step = (target < cur and RISE or FALL) * dt
      if cur < target then cur = min(cur + step, target) else cur = max(cur - step, target) end
      mult[wi] = cur
      if abs(cur - (applied[wi] or 1)) > APPLY_EPS or (cur >= 0.999 and (applied[wi] or 1) < 0.999) then
        if not wd.isTireDeflated then applyWheel(wi, cur) end
      end
      if cur < lowest then lowest = cur end
    end
  end
end

local function report()
  if not looked then findEngine() end
  local d = engineData()
  local p = obj:getPosition()
  local v3 = obj:getVelocity()
  local sp = sqrt(v3.x * v3.x + v3.y * v3.y)
  local ex, ey, ez = p.x, p.y, p.z
  if engine and engine.engineNodeID then
    local ep = obj:getAbsNodePosition(engine.engineNodeID)
    ex, ey, ez = ep.x, ep.y, ep.z
  end
  local tx, ty, tz = ex, ey, ez
  if tipNode then local tp = obj:getAbsNodePosition(tipNode) tx, ty, tz = tp.x, tp.y, tp.z end
  local rate, stored = fuelLeak()
  local oilPan, oilCooler, radiator, overheat = dmg('oilpanLeak'), dmg('oilRadiatorLeak'), dmg('radiatorLeak'), dmg('coolantOverheating')
  if forced.oil then oilPan = true end
  if forced.coolant then radiator = true end
  if forced.fuel then rate, stored = 0.4, 1 end
  local oilRate = d and d.oilLeakRateOverall or 'nil'
  local coolRate = d and d.coolantLeakRateOverall or 'nil'
  if forced.oil or forced.coolant then oilRate = forced.oil and 'nil' or oilRate coolRate = forced.coolant and 'nil' or coolRate end
  if drops then
    -- the falling drops are the game's own: one burst from the leak point per fluid that is leaking now
    local function dripOf(kind, node)
      pcall(function() obj:addParticleVelWidthTypeCount(node, vec3(0, 0, -1), vec3(0, 0, 0), 0.2, dropWidth, DROP_PARTICLE[kind], dropCount) end)
    end
    local en = engine and engine.engineNodeID
    if en then
      if oilPan or oilCooler or (type(oilRate) == 'number' and oilRate > 0.0005) then dripOf('oil', en) end
      if radiator or overheat or (type(coolRate) == 'number' and coolRate > 0.0005) then dripOf('coolant', en) end
      if rate > 0 and stored > 0 then dripOf('fuel', en) end
    end
  end
  local rpm = electrics and electrics.values and electrics.values.rpm or 0
  local temp = electrics and electrics.values and (electrics.values.watertemp or electrics.values.oiltemp) or 90
  local cold = temp < 60
  local running = rpm > 50
  if forced.exhaust then cold, running = true, true end
  obj:queueGameEngineLua(string.format('if carSurfaceFx_fluids then carSurfaceFx_fluids.car(%d,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%s,%s,%s,%s,%s,%s,%.3f,%.3f,%s,%s,%.3f)end',
    obj:getId(), sp, ex, ey, ez, tx, ty, tz, tostring(oilPan), tostring(oilCooler), tostring(radiator), tostring(overheat), tostring(oilRate), tostring(coolRate), rate, stored,
    tostring(cold), tostring(running), lowest))
end

local function frame(dt)
  if emit then
    timer = timer + dt
    if timer >= INTERVAL then timer = 0 report() end
  end
  gripFrame(dt)
end

function M.setConfig(on, exhaust, grip, fall, width, count)
  if fall ~= nil then drops = fall and true or false end
  if width then dropWidth = width end
  if count then dropCount = count end
  emit = on and true or false
  exhaustOn = exhaust and true or false
  gripOn = grip and true or false
  if not gripOn then puddles = {} end
end
function M.setPuddles(list) puddles = type(list) == 'table' and list or {} end
function M.force(kind, on) forced[kind] = on and true or nil end
-- a real puncture through the engine's own damage calls (a test: the same call a crash makes); returns what it did
function M.puncture(kind)
  if not looked then findEngine() end
  local th = engine and engine.thermals
  if not th then return 'no engine thermals' end
  if kind == 'oil' and th.applyDeformGroupDamageOilpan then th.applyDeformGroupDamageOilpan(0.1) return 'oil pan punctured' end
  if kind == 'coolant' and th.applyDeformGroupDamageRadiator then th.applyDeformGroupDamageRadiator(0.6) return 'radiator punctured' end
  if kind == 'oilcooler' and th.applyDeformGroupDamageOilRadiator then th.applyDeformGroupDamageOilRadiator(0.5) return 'oil cooler punctured' end
  return 'cannot puncture ' .. tostring(kind)
end
function M.status() return string.format('emit %s grip %s lowest %.2f puddles %d tyres %d', tostring(emit), tostring(gripOn), lowest, #puddles, wheelTread and (function() local n = 0 for _ in pairs(wheelTread) do n = n + 1 end return n end)() or 0) end

local function restore()
  if wheelTread then for wi in pairs(wheelTread) do applyWheel(wi, 1) end end
  mult, applied, lowest = {}, {}, 1
end

function M.onExtensionLoaded() looked = false end
local failed
function M.updateGFX(dt)                                      -- our code never gets to disable the vehicle: one error switches the fluids of this car off, logged once
  if failed then return end
  local ok, err = pcall(frame, dt or 0)
  if not ok then failed = tostring(err) log('E', 'carSurfaceFxFluids', 'switched off after an error: ' .. failed) end
end
function M.onReset() restore() puddles = {} timer = 0 looked = false end      -- a reset gives every tyre its full grip at once
function M.onExtensionUnloaded() pcall(restore) end

return M
