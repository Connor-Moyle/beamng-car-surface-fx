-- Car Surface FX: weather and wear on the body of every car, at runtime, with no per-car textures.
-- How: for each paint material of a car (the stages that take the car's colour or have a clear coat) the mod builds a ladder of clones
-- (<material>.cfxw1..3: darker, glossier, with a shared droplet normal map) from the material's own materials.json entry, then switches the car's
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
local CLONE = '.cfxw'                        -- clone name: <material>.cfxw1..3 (.cfxa1..3 in the assign mode)
local mode = 'fields'                        -- how clones are copied: 'fields' (getField/setField per field) or 'assign' (the engine's own field copy)
local cars = {}                               -- vehicle id -> { mats = { { name, mapTo, msc = {...} } } }
local ladders = {}                            -- material name -> what was read from it + have[rung]
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

-- what the game loaded for a material: every stage's fields and the material's own, read from the live Material object
local function readMaterial(name)
  local mat = scenetree.findObject(name)
  if not mat then return nil end
  local info = { name = name, mapTo = mat:getField('mapTo', 0), stages = {}, top = {} }
  if not info.mapTo or info.mapTo == '' then info.mapTo = name end
  for _, k in ipairs(rules.TOP_FIELDS) do info.top[k] = mat:getField(k, 0) end
  info.version, info.translucent = info.top.version, info.top.translucent
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

-- one rung: a copy of the material (everything read above) with the wet fields laid over the paint stages. Built before any car shows a rung.
local function buildRung(lad, r)
  local cloneName = lad.name .. CLONE .. r
  if scenetree.findObject(cloneName) then return true end
  local c = createObject('Material')
  if not c then return false end
  c.canSave = false
  if mode == 'assign' then
    local src = scenetree.findObject(lad.name)
    local ok, err = pcall(function() c:assignFieldsFrom(src) end)
    if not ok then log_('E', 'assignFieldsFrom failed: ' .. tostring(err)) return false end
    c:setField('name', 0, cloneName)
  else
    for k, v in pairs(lad.top) do
      if v ~= nil and v ~= '' then c:setField(k, 0, tostring(v)) end
    end
  end
  c:setField('mapTo', 0, lad.mapTo .. CLONE .. r)       -- own mapTo, so no car that spawns later binds to the clone
  for L = 0, rules.STAGES - 1 do
    local st = lad.stages[L]
    if mode ~= 'assign' then
      for k, v in pairs(st) do c:setField(k, L, v) end
    end
    if rules.isPaintStage(st) then
      for k, v in pairs(rules.wetFields(st, r)) do c:setField(k, L, v) end
    end
  end
  local fn = scenetree.findObject(lad.name):getFilename()
  if fn and fn ~= '' then pcall(function() c:setFilename(fn) end) end   -- a vehicle material knows its file (the shader's per-car paint may depend on it)
  c:registerObject(cloneName)
  Sim.upcast(c):reload()
  return true
end

-- in-place mode (rain only, no clones): the wet fields go on the original material itself, one reload per change. All cars of that model share it.
local WET_KEYS = { 'baseColorFactor', 'roughnessFactor', 'clearCoatRoughnessFactor', 'detailNormalMap', 'detailNormalMapStrength', 'detailScale' }
local function setInPlace(lad, r)
  local m = scenetree.findObject(lad.name)
  if not m then return false end
  for L = 0, rules.STAGES - 1 do
    local st = lad.stages[L]
    if rules.isPaintStage(st) then
      local wetF = r > 0 and rules.wetFields(st, r) or {}
      for _, k in ipairs(WET_KEYS) do
        local v = wetF[k] or st[k]
        if v == nil and k == 'detailNormalMap' then v = '' end
        if v ~= nil then m:setField(k, L, v) end
      end
    end
  end
  Sim.upcast(m):reload()
  lad.rung = r
  return true
end

-- find the car's body paint materials and queue their rungs
local function attach(id)
  local veh = be:getObjectByID(id)
  if not veh then return end
  local car = { mats = {}, veh = veh }
  local infos = {}
  for _, name in ipairs(veh:getMaterialNames()) do
    if not skipped(name) then
      local info = ladders[name] or readMaterial(name)
      if info then
        info.meshes = count(veh:getMeshesContainingMaterial(info.mapTo))
        infos[#infos + 1] = info
      end
    end
  end
  for name in pairs(rules.paintNames(infos)) do
    local lad = ladders[name]
    if not lad then
      for _, info in ipairs(infos) do if info.name == name then lad = info end end
      lad.have = {}
      ladders[name] = lad
      lad.rung = 0
      if mode ~= 'inplace' then for r = 1, rules.RUNGS do queue[#queue + 1] = { lad, r } end end
    end
    car.mats[#car.mats + 1] = { name = name, mapTo = lad.mapTo, lad = lad }
  end
  cars[id] = car
  log_('I', string.format('car %d: %d paint materials', id, #car.mats))
end

-- the car's mesh slots for a material. The slot's "off" material must be the original (as the game's own deform switches do, jbeam/materials.lua):
-- the first version passed the wet clone there, and resetMaterials then fell back to the clone, not the paint.
local function slots(car, m)
  if m.msc then return m.msc end
  m.msc = {}
  for mesh in string.gmatch(car.veh:getMeshesContainingMaterial(m.mapTo) or '', '%S+') do
    local s = car.veh:getSwitchableMaterial(m.mapTo, m.mapTo, mesh)
    if s >= 0 then m.msc[#m.msc + 1] = s end
  end
  return m.msc
end

local function ready(car)
  for _, m in ipairs(car.mats) do
    for r = 1, rules.RUNGS do if not m.lad.have[r] then return false end end
  end
  return true
end

-- back to the original material first, then the new rung: never rung to rung directly
local function apply(car, r)
  if not ready(car) then return false end
  for _, m in ipairs(car.mats) do
    for _, msc in ipairs(slots(car, m)) do
      car.veh:resetMaterials(msc)
      if r > 0 then car.veh:switchMaterial(msc, m.name .. CLONE .. r) end
    end
  end
  return true
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
    if q.inplace then setInPlace(q[1], q[2]) q[1].pending = nil
    elseif buildRung(q[1], q[2]) then q[1].have[q[2]] = true built = built + 1 end
  end
  timer = timer + dtReal
  if timer < 0.2 then return end
  local dt = timer
  timer = 0
  wet = forced and forced or rules.wetStep(wet, targetWet(), dt)
  local want = rules.level(wet, rung)
  local ids = wantedIds()
  for _, id in ipairs(ids) do
    local car = cars[id]
    if not car then attach(id) car = cars[id] end
    if car and mode == 'inplace' then
      for _, m in ipairs(car.mats) do
        if m.lad.rung ~= want and not m.lad.pending then m.lad.pending = true queue[#queue + 1] = { m.lad, want, inplace = true } end
      end
    elseif car and not car.slotted and ready(car) then
      for _, m in ipairs(car.mats) do slots(car, m) end
      car.slotted = true
    end
    if car and mode ~= 'inplace' and (car.rung or 0) ~= want and apply(car, want) then car.rung = want end
  end
  for id in pairs(cars) do
    if not be:getObjectByID(id) then cars[id] = nil end
  end
  rung = want
end

function M.onVehicleDestroyed(id) cars[id] = nil end
function M.onVehicleSpawned(id) cars[id] = nil end      -- a respawn gets new meshes: attach again on the next update

local function reset()
  for _, lad in pairs(ladders) do if lad.rung and lad.rung > 0 and mode == 'inplace' then setInPlace(lad, 0) end end
  for id in pairs(cars) do detach(id) end
  cars, queue, rung, wet, forced = {}, {}, 0, 0, nil
end
M.onClientEndMission = reset
M.onExtensionUnloaded = reset

-- every stage field of the original vs a clone: where they differ (the wet rungs differ in a few paint fields by design)
function M.diff(name, cloneName)
  local a, b = scenetree.findObject(name), scenetree.findObject(cloneName)
  if not a or not b then return 'missing: ' .. tostring(a ~= nil) .. ' ' .. tostring(b ~= nil) end
  local out = {}
  for L = 0, rules.STAGES - 1 do
    for _, k in ipairs(rules.STAGE_FIELDS) do
      local x, y = tostring(a:getField(k, L)), tostring(b:getField(k, L))
      if x ~= y then out[#out + 1] = string.format('L%d %s: [%s] vs [%s]', L, k, x, y) end
    end
  end
  for _, k in ipairs(rules.TOP_FIELDS) do
    local x, y = tostring(a:getField(k, 0)), tostring(b:getField(k, 0))
    if x ~= y then out[#out + 1] = string.format('top %s: [%s] vs [%s]', k, x, y) end
  end
  return #out == 0 and 'identical' or table.concat(out, ' | ')
end

-- carSurfaceFx.rebuild('fields'|'assign'|'inplace'): put the cars back to their paint, forget the clones and build them again that way
function M.rebuild(m)
  reset()
  mode = (m == 'assign' or m == 'inplace') and m or 'fields'
  CLONE = mode == 'assign' and '.cfxa' or '.cfxw'
  ladders, built = {}, 0
  return 'rebuilding with ' .. mode
end

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
  for name, lad in pairs(ladders) do mats[#mats + 1] = name .. '=' .. (lad.have[1] and 1 or 0) + (lad.have[2] and 1 or 0) + (lad.have[3] and 1 or 0) end
  return string.format('wet %.2f rung %d forced %s cars %d queue %d built %d materials [%s]', wet, rung, tostring(forced), n, #queue, built, table.concat(mats, ' '))
end

return M
