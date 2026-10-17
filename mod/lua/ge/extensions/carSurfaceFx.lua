-- Car Surface FX: weather and wear on the body of every car, at runtime, with no per-car textures.
-- How: for each paint material of a car (the stages that take the car's colour or have a clear coat) the mod builds a ladder of clones
-- (<material>.sfxw1..3: darker, glossier, with a shared droplet normal map) from the material's own materials.json entry, then switches the car's
-- meshes between the rungs with vehicle:switchMaterial (the way the game's own light/damage materials work, lua/common/jbeam/materials.lua).
-- Switching is ~free; only building a rung costs a material reload, so the rungs are built one per frame after a car appears.
-- The wetness comes from sl_weather.wetness() when Street Legal runs, else from the rain object. Settings: <user>/settings/carSurfaceFx.json.
-- Debug: carSurfaceFx.debug('rain', 1.0)  (forces the wetness, debug() clears), carSurfaceFx.status().
local M = {}
local TAG = 'carSurfaceFx'
local rules = require('carSurfaceFx/rules')

local SETTINGS_FILE = '/settings/carSurfaceFx.json'
local DEFAULTS = { rain = { enabled = true, intensity = 1 }, mud = { enabled = true, intensity = 1 }, scratch = { enabled = true, intensity = 1 }, traffic = false }
local SKIP = { 'glass', 'light', 'lens', 'window', 'windshield' }   -- name parts that are never body paint

local settings
local wet, forced, rung = 0, nil, 0          -- smoothed wetness, the debug value, the rung the cars are on
local timer = 0
local jsonCache = {}                          -- materials.json file -> its data
local cars = {}                               -- vehicle id -> { mats = { { name, mapTo, msc = {...} } } }
local ladders = {}                            -- material name -> { built = n, def = json entry }
local queue = {}                              -- clones still to build: { name, rung }
local built = 0

local function log_(level, msg) log(level, TAG, msg) end

local function loadSettings()
  settings = deepcopy(DEFAULTS)
  local s = jsonReadFile(SETTINGS_FILE)
  if type(s) ~= 'table' then jsonWriteFile(SETTINGS_FILE, DEFAULTS, true) return end
  for k, d in pairs(DEFAULTS) do
    if type(d) == 'table' and type(s[k]) == 'table' then
      if s[k].enabled ~= nil then settings[k].enabled = s[k].enabled and true or false end
      settings[k].intensity = rules.clamp(tonumber(s[k].intensity) or d.intensity, 0, 1)
    elseif type(d) == 'boolean' and s[k] ~= nil then settings[k] = s[k] and true or false end
  end
end

-- the materials.json entry of a material (its file is on the Material object)
local function definition(name)
  local mat = scenetree.findObject(name)
  if not mat then return nil end
  local fn = mat:getFilename()
  if not fn or fn == '' then return nil end
  if jsonCache[fn] == nil then jsonCache[fn] = jsonReadFile(fn) or false end
  local data = jsonCache[fn]
  return data and data[name] or nil
end

local function skipped(name)
  local n = name:lower()
  for _, part in ipairs(SKIP) do if n:find(part, 1, true) then return true end end
  return false
end

-- one rung: a copy of the material (every field of every stage) with the wet fields laid over the paint stages
local function buildRung(name, r)
  local lad = ladders[name]
  local cloneName = name .. '.sfxw' .. r
  if scenetree.findObject(cloneName) then return true end
  local def = lad.def
  local c = createObject('Material')
  if not c then return false end
  c.canSave = false
  c:setField('mapTo', 0, tostring(def.mapTo or name) .. '.sfxw' .. r)   -- own mapTo, so no car that spawns later binds to the clone
  for k, v in pairs(def) do
    if k ~= 'name' and k ~= 'mapTo' and k ~= 'Stages' and k ~= 'class' and type(v) ~= 'table' then c:setField(k, 0, rules.fieldString(v)) end
  end
  for i, st in ipairs(def.Stages or {}) do
    if type(st) == 'table' then
      for k, v in pairs(st) do c:setField(k, i - 1, rules.fieldString(v)) end
      if rules.isPaintStage(st) then
        for k, v in pairs(rules.wetFields(st, r)) do c:setField(k, i - 1, v) end
      end
    end
  end
  c:registerObject(cloneName)
  Sim.upcast(c):reload()
  return true
end

-- find the car's paint materials, queue their rungs, and remember which mesh slots to switch
local function attach(id)
  local veh = be:getObjectByID(id)
  if not veh then return end
  local car = { mats = {}, veh = veh }
  for _, name in ipairs(veh:getMaterialNames()) do
    if not skipped(name) then
      local lad = ladders[name]
      if lad == nil then
        local def = definition(name)
        lad = (def and rules.isPaintMaterial(def)) and { built = 0, def = def } or false
        ladders[name] = lad
        if lad then for r = 1, rules.RUNGS do queue[#queue + 1] = { name, r } end end
      end
      if lad then car.mats[#car.mats + 1] = { name = name, mapTo = lad.def.mapTo or name } end
    end
  end
  cars[id] = car
  log_('I', string.format('car %d: %d paint materials', id, #car.mats))
end

-- the car's mesh slots for a material, once its first rung exists (getSwitchableMaterial needs the alt material)
local function slots(car, m)
  if m.msc then return m.msc end
  local lad = ladders[m.name]
  if lad.built < 1 then return nil end
  m.msc = {}
  for mesh in string.gmatch(car.veh:getMeshesContainingMaterial(m.mapTo) or '', '%S+') do
    local s = car.veh:getSwitchableMaterial(m.mapTo, m.name .. '.sfxw1', mesh)
    if s >= 0 then m.msc[#m.msc + 1] = s end
  end
  return m.msc
end

local function apply(car, r)
  for _, m in ipairs(car.mats) do
    local s = slots(car, m)
    if s then
      local top = math.min(r, ladders[m.name].built)
      for _, msc in ipairs(s) do
        if top > 0 then car.veh:switchMaterial(msc, m.name .. '.sfxw' .. top) else car.veh:resetMaterials(msc) end
      end
    end
  end
end

local function detach(id)
  local car = cars[id]
  if not car then return end
  cars[id] = nil
  if not be:getObjectByID(id) then return end
  for _, m in ipairs(car.mats) do
    for _, msc in ipairs(m.msc or {}) do car.veh:resetMaterials(msc) end
  end
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

function M.onUpdate(dtReal)
  if not settings then loadSettings() end
  local q = queue[1]
  if q then                                         -- one clone per frame
    table.remove(queue, 1)
    local lad = ladders[q[1]]
    if buildRung(q[1], q[2]) then lad.built = math.max(lad.built, q[2]) built = built + 1 end
  end
  timer = timer + dtReal
  if timer < 0.2 then return end
  local dt = timer
  timer = 0
  wet = forced and forced or rules.wetStep(wet, targetWet(), dt)
  local want = rules.level(wet, rung)
  local ids = wantedIds()
  local changed = want ~= rung
  for _, id in ipairs(ids) do
    if not cars[id] then attach(id) changed = true end
  end
  for id in pairs(cars) do
    if not be:getObjectByID(id) then cars[id] = nil end
  end
  rung = want
  if changed or #queue > 0 then
    for _, id in ipairs(ids) do if cars[id] then apply(cars[id], rung) end end
  end
end

function M.onVehicleDestroyed(id) cars[id] = nil end
function M.onVehicleSpawned(id) cars[id] = nil end      -- a respawn gets new meshes: attach again on the next update

local function reset()
  for id in pairs(cars) do detach(id) end
  cars, queue, rung, wet, forced = {}, {}, 0, 0, nil
end
M.onClientEndMission = reset
M.onExtensionUnloaded = reset

-- carSurfaceFx.debug('rain', 1.0) forces the wetness; debug() puts the weather back
function M.debug(kind, value)
  if kind == nil then forced = nil return 'debug cleared' end
  if kind == 'rain' then
    forced = rules.clamp(tonumber(value) or 1, 0, 1)
    wet = forced
    return 'rain forced to ' .. forced
  end
  return kind .. ': not built yet'
end

function M.status()
  local n = 0
  for _ in pairs(cars) do n = n + 1 end
  local mats = {}
  for name, lad in pairs(ladders) do if lad then mats[#mats + 1] = name .. '=' .. lad.built end end
  return string.format('wet %.2f rung %d forced %s cars %d queue %d built %d materials [%s]', wet, rung, tostring(forced), n, #queue, built, table.concat(mats, ' '))
end

return M
