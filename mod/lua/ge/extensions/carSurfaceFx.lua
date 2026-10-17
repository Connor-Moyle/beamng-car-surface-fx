-- Car Surface FX: weather and wear on the body of every car, at runtime, with no per-car textures.
-- Rain: the wet look goes on each body paint material in place (darker, glossier, shared water-bead normal detail), one material reload per change,
-- spread over frames, and the original values are put back when it dries, on level change and on unload. Cars of one model share a material, so they
-- get wet together. (Clones switched per car were tried and render chrome: the hidden per-car paint state does not reach a material made from Lua.)
-- Glass: the same beads go on the glass materials (windscreen and windows) and the wipers take them off again.
-- Dirt: the car's own paint data (the same call the paint shop uses) is mixed toward dirt, per car, no reload. With settings.mud.buildup the dirt grows
-- while the wheels run on dirt/mud/sand/gravel/grass ground models (lua/vehicle/extensions/carSurfaceFxWheels.lua reports them), rain washes it off,
-- carSurfaceFx.wash() cleans it (a car wash calls that).
-- Wetness comes from sl_weather.wetness() when Street Legal runs, else from the rain object. Settings: <user>/settings/carSurfaceFx.json.
-- Debug: carSurfaceFx.debug('rain', 1.0) / ('mud', 0.8) force a value (debug() clears), carSurfaceFx.status(), carSurfaceFx.tune(scale, strength).
local M = {}
local TAG = 'carSurfaceFx'
local rules = require('carSurfaceFx/rules')

local SETTINGS_FILE = '/settings/carSurfaceFx.json'
local DEFAULTS = { rain = { enabled = true, intensity = 1 }, mud = { enabled = true, intensity = 1, buildup = false }, scratch = { enabled = true, intensity = 1 }, windscreen = { enabled = true, intensity = 1 }, traffic = false }
local SKIP = { 'glass', 'light', 'lens', 'window', 'windshield', 'plate', 'licen', 'number', 'decal' }   -- name parts that are never body paint
local WET_KEYS = { 'baseColorFactor', 'roughnessFactor', 'clearCoatRoughnessFactor', 'detailNormalMap', 'detailNormalMapStrength', 'detailScale' }

local settings
local wet, forced, rung = 0, nil, 0          -- smoothed wetness, the debug value, the rung the materials are on
local wiperBy, wiperForced = {}, nil      -- vehicle id -> wipers 0..1 reported by the car, the debug value (the wipers clear the windscreen beads)
local dirtBy = {}                          -- vehicle id -> dirt 0..1 built up by driving (settings.mud.buildup)
local forcedDirt                          -- the debug value
local timer = 0
local cars = {}                               -- vehicle id -> { veh, mats = { info... }, dirt = last applied dirt }
local mats = {}                               -- material name -> { name, stages (as first read: the originals), rung, pending }
local queue = {}                              -- material edits still to do, one per frame

local function log_(level, msg) log(level, TAG, msg) end

local function loadSettings()
  settings = deepcopy(DEFAULTS)
  local s = jsonReadFile(SETTINGS_FILE)
  if type(s) ~= 'table' then jsonWriteFile(SETTINGS_FILE, DEFAULTS, true) return end
  for k, d in pairs(DEFAULTS) do
    if type(d) == 'table' and type(s[k]) == 'table' then
      if s[k].enabled ~= nil then settings[k].enabled = s[k].enabled and true or false end
      settings[k].intensity = rules.clamp(tonumber(s[k].intensity) or d.intensity, 0, 1)
      if d.buildup ~= nil and s[k].buildup ~= nil then settings[k].buildup = s[k].buildup and true or false end
    elseif type(d) == 'boolean' and s[k] ~= nil then settings[k] = s[k] and true or false end
  end
end

local function skipped(name)
  local n = name:lower()
  for _, part in ipairs(SKIP) do if n:find(part, 1, true) then return true end end
  return false
end

local function count(str)
  local n = 0
  for _ in string.gmatch(str or '', '%S+') do n = n + 1 end
  return n
end

-- what the game loaded for a material, read from the live Material object (taken once, before the first edit)
local function readMaterial(name)
  local mat = scenetree.findObject(name)
  if not mat then return nil end
  local info = { name = name, mapTo = mat:getField('mapTo', 0), stages = {}, rung = 0, glass = rules.isGlassName(name) }
  if not info.mapTo or info.mapTo == '' then info.mapTo = name end
  info.version, info.translucent = mat:getField('version', 0), mat:getField('translucent', 0)
  for L = 0, rules.STAGES - 1 do
    local st = {}
    for _, k in ipairs(rules.STAGE_FIELDS) do
      local v = mat:getField(k, L)
      if v ~= nil and v ~= '' then st[k] = tostring(v) end
    end
    info.stages[L] = st
  end
  return info
end

-- the wet fields of rung r on the paint stages of the material itself (r = 0 puts the originals back), then one reload
local function setRung(info, r)
  local m = scenetree.findObject(info.name)
  if not m then return end
  for L = 0, info.glass and 0 or rules.STAGES - 1 do      -- glass: its first stage only
    local st = info.stages[L]
    if info.glass or rules.isPaintStage(st) then
      local wetF = r > 0 and (info.glass and rules.glassFields(st, r) or rules.wetFields(st, r)) or {}
      for _, k in ipairs(WET_KEYS) do
        local v = wetF[k] or st[k]
        if v == nil and k == 'detailNormalMap' then v = '' end
        if v ~= nil then m:setField(k, L, v) end
      end
    end
  end
  Sim.upcast(m):reload()
  info.rung = r
end

-- find the car's body paint materials (first time a material is seen its originals are read)
local function attach(id)
  local veh = be:getObjectByID(id)
  if not veh then return end
  local car = { veh = veh, mats = {} }
  local seen = {}
  for _, name in ipairs(veh:getMaterialNames()) do
    if not skipped(name) or rules.isGlassName(name) then
      local info = mats[name] or readMaterial(name)
      if info then
        info.meshes = count(veh:getMeshesContainingMaterial(info.mapTo))
        seen[#seen + 1] = info
      end
    end
  end
  for _, info in ipairs(seen) do
    if info.glass then mats[info.name] = info car.mats[#car.mats + 1] = info end
  end
  for name in pairs(rules.paintNames(seen)) do
    for _, info in ipairs(seen) do
      if info.name == name then
        mats[name] = info
        car.mats[#car.mats + 1] = info
      end
    end
  end
  cars[id] = car
  if settings.mud.buildup or settings.windscreen.enabled then M.pushGround(veh) end
  log_('I', string.format('car %d: %d paint materials', id, #car.mats))
end

-- collision-type id -> dirt weight for the level's ground models, sent to the car's wheel watcher
local function groundTable()
  local t = {}
  for name, gm in pairs(core_environment and core_environment.groundModels or {}) do
    local w = rules.groundWeight(name)
    local id = gm.cdata and gm.cdata.collisiontype
    if w > 0 and id then t[#t + 1] = string.format('[%d]=%.2f', id, w) end
  end
  return '{' .. table.concat(t, ',') .. '}'
end

function M.pushGround(veh)
  veh:queueLuaCommand('if not carSurfaceFxWheels then extensions.load("carSurfaceFxWheels") end carSurfaceFxWheels.setWeights(' .. groundTable() .. ')')
end

-- from the car's wheel watcher (lua/vehicle/extensions/carSurfaceFxWheels.lua): ground weight under the wheels, speed, seconds covered
function M.onGround(id, w, speed, dt, wipers)
  wiperBy[id] = wipers or 0
  if not (settings and settings.mud.buildup and settings.mud.enabled) then return end
  dirtBy[id] = rules.dirtStep(dirtBy[id] or 0, dt, w, speed, wet)
end

-- a car wash (or anything else that cleans): carSurfaceFx.wash() cleans the player car, wash(id, 0.5) takes off half of one car's dirt
function M.wash(id, amount)
  id = id or be:getPlayerVehicleID(0)
  dirtBy[id] = rules.clamp((dirtBy[id] or 0) - (amount or 1), 0, 1)
  return 'dirt ' .. dirtBy[id]
end

local function originalPaints(id)
  local data = core_vehicle_manager.getVehicleData(id)
  return data and data.config and data.config.paints
end

-- mix the car's paints toward dirt d (d = 0 puts the paint shop's values back)
local function setDirt(id, car, d)
  local paints = originalPaints(id)
  if not paints then return end
  for i = 1, 3 do
    if paints[i] then core_vehicle_manager.liveUpdateVehicleColors(id, car.veh, i, d > 0 and rules.dirtPaint(paints[i], d) or paints[i]) end
  end
  car.dirt = d
end

local function wantedIds()
  local ids = {}
  local pv = be:getPlayerVehicleID(0)
  if pv and pv >= 0 then ids[#ids + 1] = pv end
  if settings.traffic then
    for i = 0, be:getObjectCount() - 1 do
      local o = be:getObject(i)
      if o and o:getID() ~= pv then ids[#ids + 1] = o:getID() end
    end
  end
  return ids
end

local function targetWet()
  if forced then return forced end
  if not settings.rain.enabled then return 0 end
  local sl = rawget(_G, 'sl_weather') and sl_weather.wetness and sl_weather.wetness() or nil
  local drops = core_environment and core_environment.getPrecipitation and core_environment.getPrecipitation() or nil
  return rules.target(sl, drops) * settings.rain.intensity
end

local reset

function M.onUpdate(dtReal)
  if not settings then loadSettings() end
  if conflict() then
    if next(mats) or next(cars) then reset() log_('W', 'surfaceFXBody is loaded: Car Surface FX is paused') end
    return
  end
  local q = queue[1]
  if q then                                         -- one material reload per frame
    table.remove(queue, 1)
    setRung(q[1], q[2])
    q[1].pending = nil
  end
  timer = timer + dtReal
  if timer < 0.2 then return end
  local dt = timer
  timer = 0
  wet = forced and forced or rules.wetStep(wet, targetWet(), dt)
  local want = rules.level(wet, rung)
  if settings.mud.buildup and wet > 0 then
    for id, d in pairs(dirtBy) do dirtBy[id] = rules.washStep(d, dt, wet) end
  end
  for _, id in ipairs(wantedIds()) do
    local car = cars[id]
    if not car then attach(id) car = cars[id] end
    if car then
      local wiping = settings.windscreen.enabled and (wiperForced or wiperBy[id] or 0) > 0.1
      for _, info in ipairs(car.mats) do
        local w = want
        if info.glass and (wiping or not settings.windscreen.enabled) then w = 0 end       -- the wipers clear the glass
        if info.rung ~= w and not info.pending then info.pending = true queue[#queue + 1] = { info, w } end
      end
      local d = (forcedDirt or dirtBy[id] or 0) * settings.mud.intensity
      if not settings.mud.enabled then d = 0 end
      if math.abs(d - (car.dirt or 0)) > 0.02 or (d == 0 and (car.dirt or 0) > 0) then setDirt(id, car, d) end
    end
  end
  for id in pairs(cars) do
    if not be:getObjectByID(id) then cars[id] = nil end
  end
  rung = want
end

function M.onVehicleDestroyed(id) cars[id] = nil dirtBy[id] = nil end
function M.onVehicleSpawned(id) cars[id] = nil end      -- a respawn gets new meshes and its own paint: attach again on the next update

-- everything back to how the game had it
function reset()
  for _, info in pairs(mats) do if info.rung > 0 then setRung(info, 0) end end
  for id, car in pairs(cars) do
    if (car.dirt or 0) > 0 and be:getObjectByID(id) then setDirt(id, car, 0) end
  end
  cars, queue, rung, wet, forced, forcedDirt, dirtBy = {}, {}, 0, 0, nil, nil, {}
end
M.onClientEndMission = reset
M.onExtensionUnloaded = reset

-- carSurfaceFx.debug('rain', 1.0) / ('mud', 0.8) force a value; debug() puts the weather back
function M.debug(kind, value)
  if kind == nil then forced, forcedDirt, wiperForced = nil, nil, nil return 'debug cleared' end
  value = rules.clamp(tonumber(value) or 1, 0, 1)
  if kind == 'rain' then forced = value wet = value return 'rain forced to ' .. value end
  if kind == 'mud' then forcedDirt = value return 'mud forced to ' .. value end
  if kind == 'wiper' then wiperForced = value > 0 and value or nil return 'wipers forced to ' .. value end
  return kind .. ': not built yet'
end

-- carSurfaceFx.enable('windscreen', true) turns an effect on or off for this session (the settings file is not changed)
function M.enable(effect, on)
  if not (settings and settings[effect] and type(settings[effect]) == 'table') then return 'unknown effect' end
  settings[effect].enabled = on and true or false
  for _, car in pairs(cars) do M.pushGround(car.veh) end
  return effect .. (on and ' on' or ' off')
end

-- carSurfaceFx.tune('6 6', 0.6): size of the water beads (detailScale on the paint's UVs) and their strength; applied now to the wet materials
function M.tune(scale, strength)
  rules.beadScale = tostring(scale or rules.beadScale)
  rules.beadStrength = tonumber(strength) or rules.beadStrength
  for _, info in pairs(mats) do if info.rung > 0 then setRung(info, info.rung) end end
  return 'beads ' .. rules.beadScale .. ' strength ' .. rules.beadStrength
end

function M.status()
  local n, names = 0, {}
  for _ in pairs(cars) do n = n + 1 end
  for name, info in pairs(mats) do names[#names + 1] = name .. '=r' .. info.rung end
  local d = be:getPlayerVehicleID(0)
  return string.format('wet %.2f rung %d forced %s dirt %.2f (forced %s) cars %d queue %d wiper=%s materials [%s]', wet, rung, tostring(forced), dirtBy[d] or 0, tostring(forcedDirt), n, #queue, tostring(wiperBy[d]), table.concat(names, ' '))
end

return M
