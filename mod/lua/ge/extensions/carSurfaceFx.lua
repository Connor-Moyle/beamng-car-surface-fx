-- Car Surface FX: weather and wear on the body of every car, at runtime, with no per-car textures.
-- Rain: the wet look goes on each body paint material in place (darker, glossier, shared water-bead normal detail), one material reload per change,
-- spread over frames, and the original values are put back when it dries, on level change and on unload. Cars of one model share a material, so they
-- get wet together. (Clones switched per car were tried and render chrome: the hidden per-car paint state does not reach a material made from Lua.)
-- Glass: the windows take their base colour map from a web canvas per car and window (vehicles/common/carSurfaceFx/glass.html) that draws the original tint and animates the drops: they land, merge,
-- run down, are pushed by speed and G-force, and the wipers sweep them off. No material reload per change: only binding it and putting it back costs one.
-- Dirt: the car's own paint data (the same call the paint shop uses) is mixed toward dirt, per car, no reload. With settings.mud.buildup the dirt grows
-- while the wheels run on dirt/mud/sand/gravel/grass ground models (lua/vehicle/extensions/carSurfaceFxWheels.lua reports them), rain washes it off,
-- carSurfaceFx.wash() cleans it (a car wash calls that).
-- Wetness comes from sl_weather.wetness() when Street Legal runs, else from the rain object. Settings: <user>/settings/carSurfaceFx.json.
-- Debug: carSurfaceFx.debug('rain', 1.0) / ('mud'|'dust'|'rubber'|'grime', 0.8) force a value (debug() clears), carSurfaceFx.status(), carSurfaceFx.tune(scale, strength).
local M = {}
local TAG = 'carSurfaceFx'
local rules = require('carSurfaceFx/rules')

local SETTINGS_FILE = '/settings/carSurfaceFx.json'
local DEFAULTS = { rain = { enabled = true, intensity = 1 }, mud = { enabled = true, intensity = 1, buildup = false }, scratch = { enabled = true, intensity = 1, colour = { 0.72, 0.72, 0.70 }, opacity = 0.9, markSize = 1, dirtEnabled = true, dirtColour = { 0.28, 0.21, 0.14 }, dirtOpacity = 0.45,
    dirtSize = 0.045, dirtRate = 1, allVehicles = false }, windscreen = { enabled = true, intensity = 1 }, traffic = false }
local SKIP = { 'glass', 'light', 'lens', 'window', 'windshield', 'plate', 'licen', 'number', 'decal' }   -- name parts that are never body paint
local WET_KEYS = { 'baseColorFactor', 'roughnessFactor', 'clearCoatRoughnessFactor', 'detailNormalMap', 'detailNormalMapStrength', 'detailScale' }
local GLASS_KEYS = { 'baseColorMap' }

local settings
local wet, forced, rung = 0, nil, 0          -- smoothed wetness, the debug value, the rung the materials are on
local wiperBy, wiperForced = {}, nil      -- vehicle id -> wipers 0..1 reported by the car, the debug value (the wipers clear the windscreen beads)
local dirtBy = {}                          -- vehicle id -> { dust, mud, rubber, grime } 0..1 built up by driving (settings.mud.buildup)
local forcedDirt                          -- the debug amounts { kind = value }
local timer = 0
local cars = {}                               -- vehicle id -> { veh, mats = { info... }, dirt = last applied dirt }
local mats = {}                               -- material name -> { name, stages (as first read: the originals), rung, pending }
local motion = {}                             -- vehicle id -> { vx, vy, vz, aLong, aLat } smoothed, from the car's velocity
local GLASS_PAGE = 'local://local/vehicles/common/carSurfaceFx/glass.html'
local GLASS_SIZE, GLASS_FPS = 512, 12
local queue = {}                              -- material edits still to do, one per frame

local function log_(level, msg) log(level, TAG, msg) end
local function scratchOn() return rawget(_G, 'carSurfaceFx_scratch') ~= nil end

local function loadSettings()
  settings = deepcopy(DEFAULTS)
  local s = jsonReadFile(SETTINGS_FILE)
  if type(s) ~= 'table' then jsonWriteFile(SETTINGS_FILE, DEFAULTS, true) return end
  for k, d in pairs(DEFAULTS) do
    if type(d) == 'table' and type(s[k]) == 'table' then
      for key, dv in pairs(d) do
        local v = s[k][key]
        if type(dv) == 'boolean' and v ~= nil then settings[k][key] = v and true or false
        elseif type(dv) == 'number' and tonumber(v) then settings[k][key] = tonumber(v)
        elseif type(dv) == 'table' and type(v) == 'table' and #v == #dv then settings[k][key] = v end
      end
      settings[k].intensity = rules.clamp(settings[k].intensity or 1, 0, 1)
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
  local info = { name = name, mapTo = mat:getField('mapTo', 0), stages = {}, rung = 0, glass = rules.isGlassName(name), tag = rules.glassTag(name) }
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

-- every car that wears this (glass) material needs the canvas before the material points at it, or the glass renders garbage
local function hasCanvas(veh, tag)
  for _, t in ipairs(veh:getActiveUITextureTagNames() or {}) do if t == tag then return true end end
  return false
end

local function urlEncode(str) return (tostring(str):gsub('[^%w%-_%.~/]', function(c) return string.format('%%%02X', c:byte()) end)) end

local function wears(veh, name)
  for _, n in ipairs(veh:getMaterialNames() or {}) do if n == name then return true end end
  return false
end

local function canvases(info, on)
  for i = 0, be:getObjectCount() - 1 do
    local veh = be:getObject(i)
    if veh and wears(veh, info.name) then
      if on and not hasCanvas(veh, info.tag) then
        log_('I', 'water canvas ' .. info.tag .. ' for car ' .. veh:getID())
        veh:createUITexture(info.tag, GLASS_PAGE .. '?base=' .. urlEncode(info.stages[0].baseColorMap or ''), GLASS_SIZE, GLASS_SIZE, UI_TEXTURE_USAGE_AUTOMATIC, GLASS_FPS)
      elseif not on and hasCanvas(veh, info.tag) then veh:destroyUITexture(info.tag) end
    end
  end
end

-- the wet fields of rung r on the paint stages of the material itself (r = 0 puts the originals back), then one reload. Glass: r 1 = bound to the canvas.
local function setRung(info, r)
  local m = scenetree.findObject(info.name)
  if not m then return end
  local t0 = os.clock()
  if info.glass and r > 0 then canvases(info, true) end
  for L = 0, info.glass and 0 or rules.STAGES - 1 do      -- glass: its first stage only
    local st = info.stages[L]
    if info.glass or rules.isPaintStage(st) then
      local wetF = r > 0 and (info.glass and rules.glassFields(st, info.tag) or rules.wetFields(st, r)) or {}
      for _, k in ipairs(info.glass and GLASS_KEYS or WET_KEYS) do
        local v = wetF[k] or st[k]
        if v == nil and (k == 'detailNormalMap' or (info.glass and k == 'baseColorMap')) then v = '' end
        if v ~= nil then m:setField(k, L, v) end
      end
    end
  end
  Sim.upcast(m):reload()
  if info.glass and r == 0 then canvases(info, false) end
  info.rung = r
  info.reloadMs = (os.clock() - t0) * 1000
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

-- collision-type id -> weight for the level's ground models, in three lists (loose ground, mud, road), sent to the car's wheel watcher
local function groundTables()
  local t = { loose = {}, mud = {}, road = {} }
  for name, gm in pairs(core_environment and core_environment.groundModels or {}) do
    local class, w = rules.groundClass(name)
    local id = gm.cdata and gm.cdata.collisiontype
    if class and id then t[class][#t[class] + 1] = string.format('[%d]=%.2f', id, w) end
  end
  for k, list in pairs(t) do t[k] = '{' .. table.concat(list, ',') .. '}' end
  return t
end

function M.pushGround(veh)
  local t = groundTables()
  veh:queueLuaCommand(string.format('if not carSurfaceFxWheels then extensions.load("carSurfaceFxWheels") end carSurfaceFxWheels.setClasses(%s, %s, %s)', t.loose, t.mud, t.road))
end

-- from the car's wheel watcher (lua/vehicle/extensions/carSurfaceFxWheels.lua), every 0.5 s: the shares of that time on loose ground (weighted), mud and road,
-- skidding, and with a wheel in water; the speed; the wipers 0..1
function M.onGround(id, loose, mud, road, slip, water, speed, dt, wipers)
  wiperBy[id] = wipers or 0
  if scratchOn() and settings.scratch.dirtEnabled and speed > 2 then      -- splats around the wheels while they run on loose ground or mud
    local x = (loose * 0.8 + mud * 1.6) * settings.scratch.dirtRate
    local n = math.floor(x + math.random())
    if n > 0 then
      local muddy = mud > 0.2 or wet > 0.3
      carSurfaceFx_scratch.splat(id, muddy and { 0.20, 0.14, 0.09 } or { 0.50, 0.42, 0.30 }, settings.scratch.dirtOpacity, n, muddy and 'mud' or 'dust')
    end
  end
  if not (settings and settings.mud.buildup and settings.mud.enabled) then return end
  local d = rules.dirtBuild(dirtBy[id] or rules.dirtNew(), dt, { loose = loose, mud = mud, road = road, slip = slip }, speed, wet)
  dirtBy[id] = water > 0 and rules.dirtWash(d, dt, 0, water) or d
  if water > 0 and scratchOn() then carSurfaceFx_scratch.washSplats(id, rules.clamp(1 - water * dt / 3, 0, 1), rules.clamp(1 - water * dt / 12, 0, 1)) end
end

-- a wheel went through a puddle (Street Legal's puddlefx.wheelIn can call this): washes about two seconds' worth, more for a deeper puddle
function M.puddle(id, depth)
  if dirtBy[id] then dirtBy[id] = rules.dirtWash(dirtBy[id], 2, 0, rules.clamp((depth or 0.05) * 6, 0.1, 1)) end
end

-- a car wash (or anything else that cleans): carSurfaceFx.wash() cleans the player car, wash(id, 0.5) takes off half of one car's dirt
function M.wash(id, amount)
  id = id or be:getPlayerVehicleID(0)
  dirtBy[id] = rules.dirtClean(dirtBy[id] or rules.dirtNew(), amount)
  if scratchOn() then local f = rules.clamp(1 - (amount or 1), 0, 1) carSurfaceFx_scratch.washSplats(id, f, f) end
  return 'dirt ' .. rules.dirtTotal(dirtBy[id])
end

local function originalPaints(id)
  local data = core_vehicle_manager.getVehicleData(id)
  return data and data.config and data.config.paints
end

-- put the dirt amounts d on the car's paints (the paint shop's values when there is none)
local function setDirt(id, car, d)
  local paints = originalPaints(id)
  if not paints then return end
  local clean = rules.dirtTotal(d) <= 0
  for i = 1, 3 do
    if paints[i] then core_vehicle_manager.liveUpdateVehicleColors(id, car.veh, i, clean and paints[i] or rules.dirtPaint(paints[i], d)) end
  end
  car.dirt = d
end

local function dirtChanged(a, b)
  for _, k in ipairs(rules.KINDS) do if math.abs((a and a[k] or 0) - (b and b[k] or 0)) > 0.02 then return true end end
  return false
end

-- The scratch module (carSurfaceFx/scratch.lua + meshuv.lua, from Enhanced Skid Marks' hi-fi engine) draws real scratches where the body is hit and dirt splats around the
-- wheels on a per-car canvas. Not started while Enhanced Skid Marks' own copy runs (the two would fight over the paint layer).
local function startScratch()
  if scratchOn() or rawget(_G, 'surfaceFXHiFiScratch') ~= nil or not settings.scratch.enabled then return end
  for _, name in ipairs({ 'carSurfaceFx_meshuv', 'carSurfaceFx_scratch' }) do
    extensions.load(name)
    setExtensionUnloadMode(name, 'manual')
  end
  carSurfaceFx_scratch.configure(settings.scratch)
  log_('I', 'scratch module started')
end

local function stopScratch()
  for _, name in ipairs({ 'carSurfaceFx_scratch', 'carSurfaceFx_meshuv' }) do
    if rawget(_G, name) ~= nil then extensions.unload(name) end
  end
end

-- carSurfaceFx.repair(): buff out every car's scratches (the dirt stays); washing is the dirt's way off and never touches scratches
function M.repair() if scratchOn() then carSurfaceFx_scratch.repair() return 'scratches buffed out' end return 'scratch module is not running' end

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

-- the car's speed and its acceleration along and across it (m/s^2, smoothed), from the velocity change between ticks
local function updateMotion(id, veh, dt)
  local m = motion[id]
  if not m then m = { vx = 0, vy = 0, vz = 0, aLong = 0, aLat = 0, speed = 0, init = false } motion[id] = m end
  local v, f = veh:getVelocity(), veh:getDirectionVector()
  if not (v and f) then return m end
  if m.init and dt > 0 then
    local ax, ay, az = (v.x - m.vx) / dt, (v.y - m.vy) / dt, (v.z - m.vz) / dt
    local long = ax * f.x + ay * f.y + az * f.z
    local lat = ax * f.y - ay * f.x                         -- + to the right of the car (z up, forward f)
    m.aLong, m.aLat = m.aLong + (long - m.aLong) * 0.3, m.aLat + (lat - m.aLat) * 0.3
  end
  m.vx, m.vy, m.vz, m.init = v.x, v.y, v.z, true
  m.speed = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  return m
end

-- the water canvas of the player's car gets the weather and the car's motion; every second, cars spawned since get their canvas too
local ensureT = 0
local rainT = 0                              -- seconds since the rain last washed the splats off
function M.pushGlass(car, mo)
  local rain = forced or rules.target(nil, core_environment.getPrecipitation())      -- the rain falling now, not the wetness that lingers
  local js
  for _, info in ipairs(car.mats) do
    if info.glass and info.rung > 0 then
      js = js or ('csfxSet(' .. jsonEncode({ rain = rain * settings.windscreen.intensity, wet = wet, speed = mo.speed, aLong = mo.aLong, aLat = mo.aLat,
        wiper = wiperForced or wiperBy[car.veh:getID()] or 0, gx = rules.glassAxis.x, gy = rules.glassAxis.y, size = rules.glassSize }) .. ')')
      car.veh:queueJSUITexture(info.tag, js)
    end
  end
end

local function targetWet()
  if forced then return forced end
  if not settings.rain.enabled then return 0 end
  local sl = rawget(_G, 'sl_weather') and sl_weather.wetness and sl_weather.wetness() or nil
  local drops = core_environment and core_environment.getPrecipitation and core_environment.getPrecipitation() or nil
  return rules.target(sl, drops) * settings.rain.intensity
end

local reset
-- Enhanced Skid Marks' body extension edits the same paint fields: pause while it is loaded
local function conflict() return rawget(_G, 'surfaceFXBody') ~= nil end

local function update(dtReal)
  if settings and settings.scratch.enabled ~= scratchOn() then if settings.scratch.enabled then startScratch() else stopScratch() end end
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
  ensureT = ensureT + dtReal
  if ensureT > 1 then
    ensureT = 0
    for _, info in pairs(mats) do if info.glass and info.rung > 0 then canvases(info, true) end end
  end
  timer = timer + dtReal
  if timer < 0.2 then return end
  local dt = timer
  timer = 0
  wet = forced and forced or rules.wetStep(wet, targetWet(), dt)
  local want = rules.level(wet, rung)
  if settings.mud.buildup and wet > 0 then
    for id, d in pairs(dirtBy) do dirtBy[id] = rules.dirtWash(d, dt, wet, 0) end        -- rain
  end
  rainT = rainT + dt
  if rainT >= 5 then
    if wet > 0.05 and scratchOn() then carSurfaceFx_scratch.washSplats(nil, rules.clamp(1 - wet * rainT / 60, 0, 1), rules.clamp(1 - wet * rainT / 420, 0, 1)) end
    rainT = 0
  end
  for _, id in ipairs(wantedIds()) do
    local car = cars[id]
    if not car then attach(id) car = cars[id] end
    if car then
      local mo = updateMotion(id, car.veh, dt)
      for _, info in ipairs(car.mats) do
        local w = want
        if info.glass then w = (want > 0 and settings.windscreen.enabled and rules.glassFields(info.stages[0], info.tag).baseColorMap) and 1 or 0 end
        if info.rung ~= w and not info.pending then info.pending = true queue[#queue + 1] = { info, w } end
      end
      if id == be:getPlayerVehicleID(0) then M.pushGlass(car, mo) end
      local src = settings.mud.enabled and (forcedDirt or dirtBy[id]) or nil
      local d = rules.dirtNew()
      if src then for _, k in ipairs(rules.KINDS) do d[k] = (src[k] or 0) * settings.mud.intensity end end
      if dirtChanged(d, car.dirt) then setDirt(id, car, d) end
    end
  end
  for id in pairs(cars) do
    if not be:getObjectByID(id) then cars[id] = nil end
  end
  rung = want
end

-- One error switches the mod off (everything put back) and is logged once, instead of repeating every frame; carSurfaceFx.resume() tries again.
local failed
function M.onUpdate(dtReal)
  if failed then return end
  local ok, err = pcall(update, dtReal)
  if not ok then
    failed = tostring(err)
    log_('E', 'switched off after an error: ' .. failed .. ' (carSurfaceFx.resume() to try again)')
    pcall(reset)
  end
end

function M.resume() failed = nil return 'resumed' end

function M.onVehicleDestroyed(id) cars[id] = nil dirtBy[id] = nil motion[id] = nil end
function M.onVehicleSpawned(id) cars[id] = nil end      -- a respawn gets new meshes and its own paint: attach again on the next update

-- everything back to how the game had it
function reset()
  for _, info in pairs(mats) do if info.rung > 0 then setRung(info, 0) end end
  for id, car in pairs(cars) do
    if car.dirt and rules.dirtTotal(car.dirt) > 0 and be:getObjectByID(id) then setDirt(id, car, rules.dirtNew()) end
  end
  cars, queue, rung, wet, forced, forcedDirt, dirtBy = {}, {}, 0, 0, nil, nil, {}
end
M.onClientEndMission = reset
function M.onExtensionUnloaded() reset() stopScratch() end

-- carSurfaceFx.debug('rain', 1.0) / ('mud', 0.8) force a value; debug() puts the weather back
function M.debug(kind, value)
  if kind == nil then forced, forcedDirt, wiperForced = nil, nil, nil return 'debug cleared' end
  value = rules.clamp(tonumber(value) or 1, 0, 1)
  if kind == 'rain' then forced = value wet = value return 'rain forced to ' .. value end
  for _, k in ipairs(rules.KINDS) do
    if kind == k then forcedDirt = forcedDirt or rules.dirtNew() forcedDirt[k] = value return k .. ' forced to ' .. value end
  end
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

-- carSurfaceFx.tuneGlass('0 1', 2.5): (axis, drop size) the direction that is DOWN the glass in the glass material's UV space (differs per car: '1 0', '0 -1', '-1 0' if the water runs
-- sideways or up)
function M.tuneGlass(axis, size)
  local x, y = tostring(axis or '0 1'):match('(%-?[%d%.]+)%s+(%-?[%d%.]+)')
  if x then
    local l = math.sqrt(tonumber(x) ^ 2 + tonumber(y) ^ 2)
    if l > 0 then rules.glassAxis = { x = tonumber(x) / l, y = tonumber(y) / l } end
  end
  rules.glassSize = tonumber(size) or rules.glassSize
  return string.format('glass down = %.2f %.2f, drop size %.1f', rules.glassAxis.x, rules.glassAxis.y, rules.glassSize)
end

-- carSurfaceFx.tune('6 6', 0.6): size of the water beads (detailScale on the paint's UVs) and their strength; applied now to the wet materials
function M.tune(scale, strength)
  rules.beadScale = tostring(scale or rules.beadScale)
  rules.beadStrength = tonumber(strength) or rules.beadStrength
  for _, info in pairs(mats) do if info.rung > 0 then setRung(info, info.rung) end end
  return 'beads ' .. rules.beadScale .. ' strength ' .. rules.beadStrength
end

function M.status()
  if failed then return 'SWITCHED OFF after: ' .. failed end
  local n, names = 0, {}
  for _ in pairs(cars) do n = n + 1 end
  for name, info in pairs(mats) do names[#names + 1] = name .. '=r' .. info.rung .. (info.glass and string.format('(%.0fms)', info.reloadMs or 0) or '') end
  local d = be:getPlayerVehicleID(0)
  local dd = dirtBy[d] or rules.dirtNew()
  return string.format('wet %.2f rung %d forced %s dirt dust %.2f mud %.2f rubber %.2f grime %.2f (forced %s) cars %d queue %d wiper=%s motion=%s materials [%s]', wet, rung, tostring(forced), dd.dust, dd.mud, dd.rubber, dd.grime, tostring(forcedDirt ~= nil), n, #queue, tostring(wiperBy[d]), motion[d] and string.format('v%.1f aL%.1f aT%.1f', motion[d].speed, motion[d].aLong, motion[d].aLat) or '-', table.concat(names, ' '))
end

return M
