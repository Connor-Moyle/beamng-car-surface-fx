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
M.apiVersion = 2                          -- 2: repair(id), getState / setState, level
local rules = require('carSurfaceFx/rules')
local screen = require('carSurfaceFx/screen')
local grassRules = require('carSurfaceFx/grassRules')
local glassflow = require('carSurfaceFx/glassflow')

local SETTINGS_FILE = '/settings/carSurfaceFx.json'
local DEFAULTS = { rain = { enabled = true, intensity = 1, bodyDropMm = 4.5, glassDropMm = 10, dropAmount = 1, glassAmount = 3, impacts = 0.5, anim = 1 }, mud = { enabled = true, intensity = 1, buildup = true, rate = 1 }, scratch = { enabled = true, intensity = 1, colour = { 0.72, 0.72, 0.70 }, opacity = 0.9, markSize = 1, dirtEnabled = true, dirtColour = { 0.28, 0.21, 0.14 }, dirtOpacity = 0.45,
    dirtSize = 0.045, dirtRate = 1, water = true, allVehicles = false, dirtGlow = false, dirtGlowNits = 45000 }, windscreen = { enabled = true, windows = false, intensity = 1, overlay = true, overlayDropSize = 1.6, dropSize = 3.0, canvasSize = 1024, overlayStrength = 1 }, weather = { snow = false, snowRate = 1, frost = false, bugs = false, spray = false, frostStrength = 1, sprayStrength = 1 }, marks = { enabled = true }, fluids = { enabled = true }, impacts = { enabled = false }, ruts = { enabled = false }, traffic = false, settingsVersion = 2, grass = grassRules.DEFAULTS }
local SKIP = { 'glass', 'light', 'lens', 'lamp', 'signal', 'indicator', 'blinker', 'brake', 'reverse', 'fog', 'headl', 'taill', 'dome', 'window', 'windshield', 'plate', 'licen', 'number', 'decal' }   -- name parts that are never body paint
local WET_KEYS = { 'baseColorFactor', 'roughnessFactor', 'clearCoatRoughnessFactor', 'detailNormalMap', 'detailNormalMapStrength', 'detailScale' }
local GLASS_KEYS = { 'baseColorMap', 'emissiveMap', 'emissiveFactor', 'emissiveIntensityNits' }

local settings
local wet, forced, rung = 0, nil, 0          -- smoothed wetness, the debug value, the rung the materials are on
local doubleSided = true                  -- carSurfaceFx.glassDouble(false) to switch it off
local flood = 0                           -- debug: the window canvases solid (carSurfaceFx.debug('flood', 1))
local wiperBy, wiperForced = {}, nil      -- vehicle id -> wipers 0..1 reported by the car, the debug value (the wipers clear the windscreen beads)
local wiperHold, wiperNone = {}, {}         -- vehicle id -> os.clock() until which its wipers count as running (the reported value may be the blade's angle, which crosses zero); car has no wiper value at all
-- the wipers of a car 0..1: forced, else running when the car says so, else (no wiper value on the car) by the rain falling
local dirtBy
local function wipersOf(id, rain)
  if wiperForced then return wiperForced end
  if wiperNone[id] then return rain > 0.7 and 1 or (rain > 0.3 and 0.6 or 0) end
  return (wiperHold[id] or 0) > os.clock() and 1 or 0
end
dirtBy = {}                          -- vehicle id -> { dust, mud, rubber, grime, snow, bugs } 0..1 built up by driving and weather (settings.mud.buildup)
local glassOff                         -- debug: the window canvases are told there is no rain (carSurfaceFx.debug('glassoff', 1))
local forcedSpeed                      -- debug: the speed (m/s) the window water and the driver's view see, to test the airflow while parked
local forcedDirt                          -- the debug amounts { kind = value }
-- the film of a dirt road or a wet road on the rear glass of a car: dust, road film and mud as one amount 0..1 (the page lays it on the rear panes only); the debug amounts count for the player's car
local function filmOf(id)
  local d = (forcedDirt and id == be:getPlayerVehicleID(0)) and forcedDirt or (dirtBy and dirtBy[id])
  return d and rules.clamp((d.dust or 0) * 0.7 + (d.grime or 0) * 1.3 + (d.mud or 0) * 0.5, 0, 1) or 0
end
local frostBy, engineBy = {}, {}              -- vehicle id -> frost on its glass 0..1; its engine temperature in C as last reported
local forcedFrost, forcedSnowing, forcedAir   -- debug: frost, snowfall 0..1, air temperature C
local sheetP = 0                           -- a sheet of water thrown over the windscreen by a puddle: decays in about a second
local sprayP, sprayTarget, sprayT, forcedSpray = 0, 0, 0, nil   -- spray from the car ahead on the player's windscreen: smoothed, the last scan's, seconds since it, the debug value
local frostP = 0                           -- the player's frost: the window materials are shared by name, so they follow this car
local timer = 0
local cars = {}                               -- vehicle id -> { veh, mats = { info... }, dirt = last applied dirt }
local mats = {}                               -- material name -> { name, stages (as first read: the originals), rung, pending }
local motion = {}                             -- vehicle id -> { vx, vy, vz, aLong, aLat } smoothed, from the car's velocity
local GLASS_PAGE = 'local://local/vehicles/common/carSurfaceFx/glass.html'
local GLASS_PAGE_V = 40                    -- bumped with every change of glass.html/.js/sim.js (the browser caches pages by address)
local GLASS_SIZE, GLASS_FPS = 512, 12
local queue = {}                              -- material edits still to do, one per frame

local function log_(level, msg) log(level, TAG, msg) end
local function scratchOn() return rawget(_G, 'carSurfaceFx_scratch') ~= nil end
local function grassOn() return rawget(_G, 'carSurfaceFx_grass') ~= nil end

-- the settings file, <user>/settings/carSurfaceFx.json, is the one store; the Mods menu (Wrench Works' slrr_settings, see carSurfaceFx/schema.lua) reads and writes it
local screenSize = 4.5

local function loadSettings()
  settings = deepcopy(DEFAULTS)
  local s = jsonReadFile(SETTINGS_FILE)
  if type(s) ~= 'table' then jsonWriteFile(SETTINGS_FILE, DEFAULTS, true) rules.glassSize, screenSize = settings.windscreen.dropSize, settings.windscreen.overlayDropSize return end
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
  rules.glassSize, screenSize = settings.windscreen.dropSize, settings.windscreen.overlayDropSize
  local on, _, moved = rules.migrate(s, nil)
  if moved then                                                      -- one time, see rules.migrate
    if on then settings.mud.buildup = true end
    settings.settingsVersion = rules.SETTINGS_VERSION
    jsonWriteFile(SETTINGS_FILE, settings, true)
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
  local info = { name = name, mapTo = mat:getField('mapTo', 0), stages = {}, rung = 0, glass = rules.isGlassName(name), tag = rules.glassTag(name), mode = rules.glassMode(name) }
  if not info.mapTo or info.mapTo == '' then info.mapTo = name end
  info.version, info.translucent = mat:getField('version', 0), mat:getField('translucent', 0)
  info.doubleSided = mat:getField('doubleSided', 0)
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

-- the player's windows get the finer canvas when the setting says so (windscreen.canvasSize 1024: a bead is then about 2 mm of glass per texel); other cars always 512
local function glassSizeFor(veh) return (veh:getID() == be:getPlayerVehicleID(0) and (settings.windscreen.canvasSize or 512) >= 1024) and 1024 or GLASS_SIZE end

local function canvases(info, on)
  for i = 0, be:getObjectCount() - 1 do
    local veh = be:getObject(i)
    if veh and wears(veh, info.name) then
      if on and not hasCanvas(veh, info.tag) then
        log_('I', 'water canvas ' .. info.tag .. ' for car ' .. veh:getID())
        local _, src = rules.glassMap(info.stages[0], info.mode)
        veh:createUITexture(info.tag, GLASS_PAGE .. '?mode=' .. info.mode .. '&v=' .. GLASS_PAGE_V .. '&base=' .. urlEncode(src or ''), glassSizeFor(veh), glassSizeFor(veh), UI_TEXTURE_USAGE_AUTOMATIC, GLASS_FPS)
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
    local palette = false
    for _, s2 in pairs(info.stages) do if rules.isPaintStage(s2) then palette = true end end
    if info.glass or rules.isPaintStage(st) or (not palette and L == 0 and st) then      -- a material without a palette (trim, a carbon roof) is wetted on its first stage
      local wetF = r > 0 and (info.glass and rules.glassFields(st, info.tag, info.mode) or rules.wetFields(st, r, info.trim)) or {}
      for _, k in ipairs(info.glass and GLASS_KEYS or WET_KEYS) do
        local v = wetF[k] or st[k]
        if v == nil and (k == 'detailNormalMap' or (info.glass and (k == 'baseColorMap' or k == 'emissiveMap'))) then v = ''
        elseif v == nil and info.glass and k == 'emissiveFactor' then v = '0 0 0' end
        if v ~= nil then m:setField(k, L, v) end
      end
    end
  end
  if info.glass and info.mode == 'color' then               -- the outside pane is also what the cockpit looks through when the inside pane shows nothing: draw its back face too while wet
    m:setField('doubleSided', 0, (r > 0 and doubleSided) and '1' or tostring(info.doubleSided or '0'))
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
  local paint = rules.paintNames(seen)
  for name in pairs(paint) do
    for _, info in ipairs(seen) do
      if info.name == name then
        mats[name] = info
        car.mats[#car.mats + 1] = info
      end
    end
  end
  for name in pairs(rules.trimNames(seen, paint)) do                  -- bumpers, trim, mirrors, wheels, seals: the rest of the outside gets wet too
    for _, info in ipairs(seen) do
      if info.name == name and not mats[name] then
        info.trim = true
        mats[name] = info
        car.mats[#car.mats + 1] = info
      end
    end
  end
  cars[id] = car
  local glassMat = {}
  for _, info in ipairs(car.mats) do if info.glass then glassMat[info.mapTo] = true glassMat[info.name] = true end end
  if next(glassMat) then                                             -- which way water runs on each pane, from the car's own mesh (carSurfaceFx/glassflow.lua)
    car.flowAt = {}
    glassflow.request(id, glassMat, function(f) if cars[id] == car then car.flow = f end end)
  end
  if settings.mud.buildup or settings.windscreen.enabled then M.pushGround(veh) end
  log_('I', string.format('car %d: %d materials (paint and glass)', id, #car.mats))
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

-- the game's time of day 0..1 (0 noon, 0.5 midnight), or nil
local function timeOfDay()
  local t = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
  return type(t) == 'table' and tonumber(t.time) or nil
end
local wetSecs = 0                          -- seconds of rain so far: grows while it rains, falls back when dry (rain loosens dried bugs, washes dust from the top down)

-- air temperature in C (the level's), or nil when the game does not say
local function airC()
  if forcedAir then return forcedAir end
  local k = core_environment and core_environment.getTemperatureK and core_environment.getTemperatureK()
  return type(k) == 'number' and k - 273.15 or nil
end
local function snowfall() return forcedSnowing or rules.snowing(core_environment and core_environment.getPrecipitation and core_environment.getPrecipitation() or 0, airC()) end

-- Dirt where it really lands on the body (carSurfaceFx/bodymap.lua, through carSurfaceFx_scratch.dirtAt): as an amount grows, splats of that kind are put on the places its rule
-- picks: mud sprayed off the tyres (low, behind the wheels, streaks), the road film on the lower body and the rear faces, dust, rubber around the wheels, snow on flat sky-facing
-- surfaces only, bugs on the nose. The colours: mud brown and earthy, dust a light tan, the road film dark grey, rubber black, snow white. Without the car's body map (no source mesh
-- yet) the plain regions of the old placement are used.
local COL = { mud = { 0.66, 0.50, 0.34 }, dust = { 0.66, 0.57, 0.42 }, grime = { 0.24, 0.23, 0.21 }, rubber = { 0.04, 0.04, 0.04 }, snow = { 0.95, 0.96, 0.98 }, bugs = { 0.12, 0.10, 0.06 } }
local PLACE = {   -- kind: splats per unit of amount, opacity, radius in metres, the plain region and kind of the old placement
  mud = { 3000, 0.9, 0.03 }, dust = { 180, 0.45, 0.06 }, grime = { 220, 0.30, 0.05 }, rubber = { 250, 0.9, 0.018 }, snow = { 200, 0.95, 0.10 }, bugs = { 120, 0.85, 0.012 },
}
local FALL = { mud = { 'lowL', 'mud', 1.5 }, dust = { 'lowL', 'dust', 1.8 }, snow = { 'top', 'dust', 2.2 }, bugs = { 'front', 'mud', 0.35 } }
local function bodyDirt(id, kind, amount, wi)
  if amount <= 0 or not (scratchOn() and settings.scratch.dirtEnabled) then return end
  local pl = PLACE[kind]
  if kind == 'bugs' then pl = { pl[1], pl[2], pl[3] * rules.bugSize(dirtBy[id] and dirtBy[id].bugs) } end      -- the more bugs, the bigger the next ones
  local n = math.floor(amount * pl[1] * (settings.scratch.dirtRate or 1) + math.random())      -- (the Splat rate setting: fewer splats for a slower machine)
  if n <= 0 then return end
  local sc = carSurfaceFx_scratch
  local vd = core_vehicle_manager and core_vehicle_manager.getVehicleData(id)
  local pp = vd and vd.config and vd.config.paints
  local pc = pp and pp[1] and pp[1].baseColor
  if pc and sc.setPaintLum then sc.setPaintLum(id, 0.2126 * (pc[1] or 0) + 0.7152 * (pc[2] or 0) + 0.0722 * (pc[3] or 0)) end
  local opts = kind == 'dust' and { maxH = rules.dustHeight(dirtBy[id] and dirtBy[id].dust or amount), washH = rules.dustWashHeight(wetSecs) } or nil       -- the film climbs with the amount, rain takes the top of it
  if sc.dirtAt(id, kind, n, wi, COL[kind], pl[2], pl[3], opts) then
    if kind == 'dust' then sc.dirtAt(id, 'dust', math.max(2, n), nil, COL.dust, 0.10, 0.30, { maxH = 1, washH = opts.washH, film = true }) end      -- and a faint haze over the whole body, the roof and bonnet too
    return
  end
  local f = FALL[kind]
  if not f then return end                                          -- the road film and rubber need the body map
  sc.bodySplat(id, f[1], COL[kind], pl[2], n, f[2], f[3])
  if f[1] == 'lowL' then sc.bodySplat(id, 'lowR', COL[kind], pl[2], n, f[2], f[3]) end
end

local function weatherSplats(id, old, new)
  if not scratchOn() then return end
  local ds, db = new.snow - old.snow, new.bugs - old.bugs
  if ds > 0 then bodyDirt(id, 'snow', ds)
  elseif ds < 0 and old.snow > 0 then carSurfaceFx_scratch.washSplats(id, rules.clamp(new.snow / old.snow, 0, 1), 1) end
  if db > 0 then bodyDirt(id, 'bugs', db) end
end

local function dirtSplats(id, old, new)
  for _, kind in ipairs({ 'mud', 'dust', 'grime', 'rubber' }) do
    local d = (new[kind] or 0) - (old[kind] or 0)
    if d > 0 then bodyDirt(id, kind, d) end
  end
end

-- from the car's wheel watcher (lua/vehicle/extensions/carSurfaceFxWheels.lua), every 0.5 s: the shares of that time on loose ground (weighted), mud and road,
-- skidding, and with a wheel in water; the speed; the wipers 0..1
-- splash from your own wheels in a puddle: dirty water up the lower body on the sides whose wheels were in it, a sheet over the windscreen for a deep one at speed
local function splash(id, shareL, shareR, speed, depth)
  local nL, nR, sheet = rules.splash(speed, shareL, shareR, depth)
  if nL + nR <= 0 and sheet <= 0 then return end
  if scratchOn() and settings.scratch.dirtEnabled then
    local c = { 0.26, 0.21, 0.15 }
    local a, b = math.floor(nL + math.random()), math.floor(nR + math.random())
    if a > 0 then carSurfaceFx_scratch.bodySplat(id, 'lowL', c, 0.7, a, 'mud', 1.1) end
    if b > 0 then carSurfaceFx_scratch.bodySplat(id, 'lowR', c, 0.7, b, 'mud', 1.1) end
  end
  if id == be:getPlayerVehicleID(0) and settings.weather.spray and sheet > sheetP then sheetP = sheet end
end

local groundCalls, groundAt = 0, 0
function M.onGround(id, loose, mud, road, slip, water, speed, dt, wipers, engine, waterL, waterR, spin)
  groundCalls, groundAt = groundCalls + 1, os.clock()
  wipers = tonumber(wipers) or 0
  wiperBy[id], wiperNone[id] = wipers, wipers < 0
  if wipers > 0.05 then wiperHold[id] = os.clock() + 3 end
  engineBy[id] = tonumber(engine)
  if grassOn() then carSurfaceFx_grass.noteGround(id, loose, mud, slip, speed) end
  if (waterL or 0) + (waterR or 0) > 0 then splash(id, waterL or 0, waterR or 0, speed, 0.5 + 0.5 * math.min(1, (water or 0))) end
  if scratchOn() and settings.scratch.dirtEnabled and speed > 2 then      -- splats around the wheels while they run on loose ground or mud
    local x = (loose * 0.8 + mud * 1.6) * settings.scratch.dirtRate * 0.4
    local n = math.floor(x + math.random())
    if n > 0 then
      local muddy = mud > 0.2 or wet > 0.3
      carSurfaceFx_scratch.splat(id, muddy and { 0.42, 0.30, 0.20 } or { 0.55, 0.48, 0.36 }, settings.scratch.dirtOpacity, n, muddy and 'mud' or 'dust')
    end
  end
  if not (settings and settings.mud.enabled) then return end
  local old = dirtBy[id] or rules.dirtNew()
  local air = airC()
  local d = rules.dirtBuild(old, dt * settings.mud.rate, { loose = loose, mud = mud, road = road, slip = slip, spin = tonumber(spin), snowing = settings.weather.snow and snowfall() * (settings.weather.snowRate or 1) / math.max(settings.mud.rate, 0.01) or 0, warm = air ~= nil and air > rules.SNOW_AIR,
    airC = air, tod = timeOfDay() }, speed, wet)
  if not settings.mud.buildup then for _, k in ipairs({ 'dust', 'mud', 'rubber', 'grime' }) do d[k] = old[k] end end       -- only the weather kinds build without the build-up setting
  if not settings.weather.snow then d.snow = old.snow end
  if not settings.weather.bugs then d.bugs = old.bugs end
  if water > 0 then d = rules.dirtWash(d, dt, 0, water) end
  dirtBy[id] = d
  weatherSplats(id, old, d)
  dirtSplats(id, old, d)
  if water > 0 and scratchOn() then carSurfaceFx_scratch.washSplats(id, rules.clamp(1 - water * dt / 3, 0, 1), rules.clamp(1 - water * dt / 12, 0, 1)) end
end

-- a wheel went through a puddle (Street Legal's puddlefx.wheelIn can call this): washes about two seconds' worth, more for a deeper puddle
function M.puddle(id, depth)
  local m = motion[id or be:getPlayerVehicleID(0)]
  if m then splash(id or be:getPlayerVehicleID(0), 1, 1, m.speed, rules.clamp((depth or 0.05) * 6, 0.1, 1)) end
  if dirtBy[id] then dirtBy[id] = rules.dirtWash(dirtBy[id], 2, 0, rules.clamp((depth or 0.05) * 6, 0.1, 1)) end
end

-- a car wash (or anything else that cleans): carSurfaceFx.wash() cleans the player car, wash(id, 0.5) takes off half of one car's dirt
function M.wash(id, amount)
  id = id or be:getPlayerVehicleID(0)
  if forcedDirt and id == be:getPlayerVehicleID(0) then forcedDirt = nil end      -- a debug amount would show the dirt through the wash
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
  for _, name in ipairs({ 'carSurfaceFx_meshuv', 'carSurfaceFx_scratch', 'carSurfaceFx_bodywear' }) do
    setExtensionUnloadMode(name, 'manual')
    extensions.load(name)
  end
  carSurfaceFx_scratch.configure(settings.scratch)
  log_('I', 'scratch module started')
end

local function marksOn() return rawget(_G, 'carSurfaceFx_marks') ~= nil end
local function startMarks()
  if marksOn() or not settings.marks.enabled then return end
  setExtensionUnloadMode('carSurfaceFx_marks', 'manual')
  extensions.load('carSurfaceFx_marks')
  log_('I', 'marks module started')
end
local function stopMarks()
  if marksOn() then extensions.unload('carSurfaceFx_marks') end
end

local function fluidsOn() return rawget(_G, 'carSurfaceFx_fluids') ~= nil end
local function startFluids()
  if fluidsOn() or not settings.fluids.enabled then return end
  setExtensionUnloadMode('carSurfaceFx_fluids', 'manual')
  extensions.load('carSurfaceFx_fluids')
  log_('I', 'leaking fluids module started')
end
local function stopFluids()
  if fluidsOn() then extensions.unload('carSurfaceFx_fluids') end
end

local function rutsOn() return rawget(_G, 'carSurfaceFx_ruts') ~= nil end
local function startRuts()
  if rutsOn() or not settings.ruts.enabled then return end
  setExtensionUnloadMode('carSurfaceFx_ruts', 'manual')
  extensions.load('carSurfaceFx_ruts')
  log_('I', 'ruts module started')
end
local function stopRuts()
  if rutsOn() then extensions.unload('carSurfaceFx_ruts') end
end

local function impactsOn() return rawget(_G, 'carSurfaceFx_impacts') ~= nil end
local function startImpacts()
  if impactsOn() or not settings.impacts.enabled then return end
  setExtensionUnloadMode('carSurfaceFx_impacts', 'manual')
  extensions.load('carSurfaceFx_impacts')
  log_('I', 'crash effects module started (glass, debris, sparks)')
end
local function stopImpacts()
  if impactsOn() then extensions.unload('carSurfaceFx_impacts') end
end

-- Tyre wear, temperature and grip (carSurfaceFx/tyres.lua + the car module). Runs while settings.tyres.enabled (off by default until shown in the game).
local function tyresOn() return rawget(_G, 'carSurfaceFx_tyres') ~= nil end
local tyresWanted = false                             -- the Tyres page's switch (file settings/carSurfaceFx_tyres.json), read when the settings are loaded
local function readTyresFlag()
  local f = jsonReadFile(require('carSurfaceFx/tyresSchema').FILE)
  tyresWanted = type(f) == 'table' and f.enabled == true
  if tyresOn() then carSurfaceFx_tyres.reload() end
end
local function startTyres()
  if tyresOn() or not tyresWanted then return end
  setExtensionUnloadMode('carSurfaceFx_tyres', 'manual')
  extensions.load('carSurfaceFx_tyres')
  carSurfaceFx_tyres.reload()
  log_('I', 'tyre module started')
end
local function stopTyres()
  if tyresOn() then carSurfaceFx_tyres.configure({ enabled = false }) extensions.unload('carSurfaceFx_tyres') end
end

-- Grass that bends under the wheels (carSurfaceFx/grass.lua): the game's own surface mask, stamped from the wheels. Runs while settings.grass.enabled.
local function startGrass()
  if grassOn() or not settings.grass.enabled then return end
  setExtensionUnloadMode('carSurfaceFx_grass', 'manual')
  extensions.load('carSurfaceFx_grass')
  if carSurfaceFx_grass then carSurfaceFx_grass.configure(settings.grass) end
  log_('I', 'grass module started')
end
local function stopGrass()
  if grassOn() then extensions.unload('carSurfaceFx_grass') end
end

local function stopScratch()
  for _, name in ipairs({ 'carSurfaceFx_bodywear', 'carSurfaceFx_scratch', 'carSurfaceFx_meshuv' }) do
    if rawget(_G, name) ~= nil then extensions.unload(name) end
  end
end

-- carSurfaceFx.repair(id): buff out the scratches of that car (the player's when nil; the dirt stays); washing is the dirt's way off and never touches scratches
function M.repair(id)
  if not scratchOn() then return 'scratch module is not running' end
  id = id or be:getPlayerVehicleID(0)
  carSurfaceFx_scratch.repair(id)
  return 'scratches buffed out on car ' .. tostring(id)
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

-- road spray: every 0.25 s at most, look for a car ahead of the player's (rules.spray); trucks by their length. Smoothed so it builds and fades.
local function scanSpray(dt, pv, wetNow)
  sprayT = sprayT + dt
  if sprayT >= 0.25 then
    sprayT = 0
    local t = 0
    if pv and settings.weather.spray and wetNow > 0.2 then
      local pp, f = pv:getPosition(), pv:getDirectionVector()
      for i = 0, be:getObjectCount() - 1 do
        local o = be:getObject(i)
        if o and o:getID() ~= pv:getID() then
          local p = o:getPosition()
          local dx, dy = p.x - pp.x, p.y - pp.y
          if dx * dx + dy * dy < 900 then
            local of, v = o:getDirectionVector(), o:getVelocity()
            local ok, len = pcall(function() return o:getInitialLength() end)
            t = t + rules.spray({ dist = dx * f.x + dy * f.y, lateral = dx * f.y - dy * f.x, align = of.x * f.x + of.y * f.y, speed = math.sqrt(v.x * v.x + v.y * v.y),
              len = ok and tonumber(len) or 4.5 })
          end
        end
      end
    end
    sprayTarget = rules.clamp(t * rules.sprayWet(wetNow), 0, 1)
  end
  sheetP = sheetP * math.exp(-dt * 1.8)
  if sheetP < 0.01 then sheetP = 0 end
  local goal = forcedSpray or math.max(sprayTarget, sheetP)
  sprayP = sprayP + (goal - sprayP) * math.min(1, dt * 3)
  if sprayP < 0.005 and goal == 0 then sprayP = 0 end
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
-- what the windows and the driver view show of frost and road spray: the real amount times the amount the player chose (0 shows none; the weather itself goes on, so turning it
-- back up shows the true state). The driver-view amounts are an accessibility setting: drops, frost and mist can each be turned down or off on their own.
local function frostShown() return frostP * (settings.weather.frostStrength or 1) end
local function sprayShown() return sprayP * (settings.weather.sprayStrength or 1) end
-- carSurfaceFx.glassDebug(true): the window canvases show their glass cells and the page's numbers (drops, flow, cells, rain, size) written on the glass
-- carSurfaceFx.glassDebug('drops'): no grid, only the live drops, drawn eight times their size in solid white (is it the look, or the place?)
local glassDbg = false
function M.glassDebug(on) glassDbg = on == 'drops' and 'drops' or (on and true or false) return 'glass debug ' .. tostring(glassDbg) end

function M.pushGlass(car, mo)
  local rain = forced or rules.target(nil, core_environment.getPrecipitation())      -- the rain falling now, not the wetness that lingers
  local wetG = wet
  if glassOff then rain, wetG = 0, 0 end                                                -- debug: the window canvases stay clear while the driver's view keeps drawing
  local js
  -- from the driver's seat the inside panes are close to the eye and their drops are big soft blobs: the overlay draws the windscreen's water, so these stay clear (the player's own car only)
  local inside = settings.windscreen.overlay and car.veh:getID() == be:getPlayerVehicleID(0) and core_camera and core_camera.getActiveCamName and ({ driver = true, onboard = true })[core_camera.getActiveCamName(0)]
  for _, info in ipairs(car.mats) do
    local clear = inside and tostring(info.name or info.tag):find('_int', 1, true)
    if info.glass and info.rung > 0 and hasCanvas(car.veh, info.tag) then                    -- (a new car's canvases are made over the next ticks: nothing is sent before they exist)
      local field = car.flow and (car.flow[info.mapTo] or car.flow[info.name])
      js = ('csfxSet(' .. jsonEncode({ glassMm = settings.rain.glassDropMm, amount = settings.rain.dropAmount * (settings.rain.glassAmount or 3), imp = settings.rain.impacts, dbg = glassDbg == 'drops' and 2 or (glassDbg and 1 or 0), uvPerM = field and field.uvPerM or 0.5, rain = clear and 0 or rain * settings.windscreen.intensity, wet = clear and 0 or wetG, speed = forcedSpeed or mo.speed, aLong = mo.aLong, aLat = mo.aLat,
        wiper = wipersOf(car.veh:getID(), rain), film = filmOf(car.veh:getID()), gx = rules.glassAxis.x, gy = rules.glassAxis.y, size = rules.glassSize, tint = rules.glassTint, passes = rules.glassPasses, flood = flood, frost = frostP, spray = sprayP }) .. ')')
      car.veh:queueJSUITexture(info.tag, js)
    end
  end
end

local function targetWet()
  if forced then return forced end
  if not settings.rain.enabled then return 0 end
  local sl = rawget(_G, 'sl_weather') and sl_weather.wetness and sl_weather.wetness() or nil
  local drops = core_environment and core_environment.getPrecipitation and core_environment.getPrecipitation() or nil
  if snowfall() > 0.3 then drops = 0 end                    -- snow is not water
  return rules.target(sl, drops) * settings.rain.intensity
end

local reset
-- The old Surface FX / Enhanced Skid Marks (dirtSkidMarks) is what this mod now contains: if it is loaded as well it is switched off (its extensions unloaded, on the cars too)
-- and the player is told once to remove it. Its own versions of everything run here.
local OLD_GE = { 'dirtSkidManager', 'surfaceFX', 'surfaceFXStore', 'surfaceFXBody', 'surfaceFXGlass', 'surfaceFXDebris', 'surfaceFXSparks', 'surfaceFXHiFiScratch', 'surfaceFXMeshUV',
  'surfaceFXDebug', 'dirtDeform', 'dirtScratch' }
local OLD_VEH = "{'dirtSkidWheels','dirtSkidBody','dirtScratchBody','dirtSkidDrips','dirtGrip','dirtGlass','dirtDebris','dirtSparks','dirtScratchHiFi','dirtDeformWheels'}"
local oldTold = false
local SHIMS = { surfaceFX = true, surfaceFXStore = true, surfaceFXBody = true }
local function retireOldMod()
  local found = false
  for _, n in ipairs(OLD_GE) do
    local g = rawget(_G, n)
    if g ~= nil and not (type(g) == 'table' and g.csfxShim) then       -- our own compatibility modules (surfaceFX, surfaceFXStore, surfaceFXBody) are not the old mod
      found = true
      pcall(extensions.unload, n)
      if SHIMS[n] then pcall(extensions.load, n) end                  -- the old one is gone: ours takes the name back
    end
  end
  if not found then return end
  for _, v in ipairs(getAllVehicles()) do
    v:queueLuaCommand('for _, n in ipairs(' .. OLD_VEH .. ') do if rawget(_G, n) ~= nil then extensions.unload(n) end end')
  end
  if not oldTold then
    oldTold = true
    log_('W', 'the old Surface FX / Enhanced Skid Marks mod is installed as well: switched off, Car Surface FX has all of its features. Please remove the old mod (dirtSkidMarks).')
    if guihooks and guihooks.message then guihooks.message('Car Surface FX now includes Surface FX (Enhanced Skid Marks). The old mod was switched off for this session: please remove it from your mods.', 20, 'csfx') end
  end
end
local retireT = 1

-- The driver's view: the inside pane of the windscreen cannot show the canvas (see docs/DESIGN.md), so while the camera looks through a wet windscreen the game's web UI layer
-- (ui/modModules/csfxRain) draws the drops on the screen, clipped to the windscreen's outline, which is projected from its nodes about 15 times a second.
local DRIVER_CAMS = { driver = true, onboard = true }
local screenT, screenOn, screenDebug, screenCam, overlayReport = 0, false, false, nil, ''
local screenWhy = {}      -- (the reason is kept as values and made into text only when asked, not at 15 Hz)
local screenTrace, traceT = false, 0      -- carSurfaceFx.screenTrace(true): the reason is written to the log once a second
local function pushScreen(dt)
  screenT = screenT + dt
  if screenT < 0.066 then return end
  screenT = 0
  local pv = be:getPlayerVehicle(0)
  local cam = core_camera and core_camera.getActiveCamName and core_camera.getActiveCamName(0)
  local drops = settings.windscreen.overlayStrength or 1
  local want = pv and settings.windscreen.enabled and settings.windscreen.overlay and DRIVER_CAMS[cam] and ((wet > 0.03 and drops > 0.01) or frostShown() > 0.03 or sprayShown() > 0.03)
  if cam ~= screenCam then screenCam = cam if pv then screen.resetEye(pv:getID()) end end              -- another camera has another eye position
  local hull = want and screen.windscreen(pv) or nil
  screenWhy.cam, screenWhy.wet, screenWhy.overlay, screenWhy.want, screenWhy.hull, screenWhy.on = cam, wet, settings.windscreen.overlay, want and true or false, hull and #hull / 2 or nil, screenOn
  if screenTrace then
    traceT = traceT + 0.066
    if traceT >= 1 then
      traceT = 0
      local mo = pv and motion[pv:getID()]
      log_('I', 'screen trace: ' .. M.screenInfo() .. string.format(' speed=%.1f aLong=%.1f rain=%.2f sprayP=%.2f frostP=%.2f wiper=%s nodes=%s',
        mo and mo.speed or -1, mo and mo.aLong or 0, forced or rules.target(nil, core_environment.getPrecipitation()), sprayP, frostP, tostring(pv and wipersOf(pv:getID(), 1)), tostring(pv and screen.windscreenNodeCount and screen.windscreenNodeCount(pv:getID()))))
    end
  end
  if not hull then
    if screenOn then guihooks.trigger('csfxScreen', { on = false }) screenOn = false end
    return
  end
  local mo = motion[pv:getID()] or { speed = 0, aLong = 0, aLat = 0 }
  local rain = forced or rules.target(nil, core_environment.getPrecipitation())
  guihooks.trigger('csfxScreen', { on = true, hull = hull, rain = rain * settings.windscreen.intensity * drops, wet = wet * drops, speed = forcedSpeed or mo.speed, aLong = mo.aLong, aLat = mo.aLat,
    wiper = wipersOf(pv:getID(), rain), size = screenSize, debug = screenDebug, frost = frostShown(), spray = sprayShown() })
  screenOn = true
end

-- carSurfaceFx.tuneScreen(3.0): drop size of the overlay in the driver's view
-- carSurfaceFx.screenInfo(true): why the overlay is on or off; true also draws the windscreen's outline and a counter on the screen
function M.screenInfo(dbg)
  if dbg ~= nil then screenDebug = dbg and true or false end
  local w = screenWhy
  return 'cam=' .. tostring(w.cam) .. ' wet=' .. string.format('%.2f', w.wet or 0) .. ' overlay=' .. tostring(w.overlay) .. ' want=' .. tostring(w.want or false) .. ' hull=' .. (w.hull or 'nil') .. ' on=' .. tostring(w.on or false) .. ' debug=' .. tostring(screenDebug) .. ' | ' .. M.screenDiag()
end

-- carSurfaceFx.windscreenDump(): the windscreen flexbodies and their nodes in the car's frame, written to /settings/csfx_windscreen_nodes.json
function M.windscreenDump()
  local veh = be:getPlayerVehicle(0)
  if not veh then return 'no car' end
  local out = screen.dump(veh)
  jsonWriteFile('/settings/csfx_windscreen_nodes.json', out, true)
  return string.format('%d windscreen flexbodies, %s nodes in the first: written to /settings/csfx_windscreen_nodes.json', #out.flexbodies, out.flexbodies[1] and #out.flexbodies[1].nodes or 0)
end

-- what the projection and the overlay see: speed, how far the camera position was corrected, the windscreen's box on the screen, the points projected, and the last report of the page
function M.screenDiag()
  local l = screen.last
  return string.format('speed %.1f eyeFix %.2f m box %s points %s clipped %s | %s | page: %s', l.speed or 0, l.fix or 0, tostring(l.box), tostring(l.points), l.clipped and 'to the screen' or 'no', tostring(l.camera), overlayReport)
end

-- the overlay page reports (debug on): its drop count, frame rate and the box it draws in, once a second; also written to the log
function M.overlayReport(text)
  overlayReport = tostring(text)
  if screenDebug then log_('I', 'overlay ' .. overlayReport .. ' | ' .. M.screenDiag()) end
end

-- carSurfaceFx.screenTrace(true): once a second, why the cockpit overlay is on or off (camera, wetness, the overlay setting, the hull, the car's speed, the rain value,
-- the wipers, how many nodes the windscreen has) goes to beamng.log; false stops it
function M.screenTrace(on) screenTrace = on and true or false traceT = 1 return 'screen trace ' .. tostring(screenTrace) end

function M.tuneScreen(size) screenSize = tonumber(size) or screenSize return 'overlay drop size ' .. screenSize end

-- starts and stops each module to match its switch (kept out of update(): LuaJIT allows 60 upvalues per function)
local function syncModules()
  if settings and settings.scratch.enabled ~= scratchOn() then if settings.scratch.enabled then startScratch() else stopScratch() end end
  if settings and settings.marks.enabled ~= marksOn() then if settings.marks.enabled then startMarks() else stopMarks() end end
  if settings and settings.fluids and settings.fluids.enabled ~= fluidsOn() then if settings.fluids.enabled then startFluids() else stopFluids() end end
  if settings and settings.ruts and settings.ruts.enabled ~= rutsOn() then if settings.ruts.enabled then startRuts() else stopRuts() end end
  if settings and settings.impacts and settings.impacts.enabled ~= impactsOn() then if settings.impacts.enabled then startImpacts() else stopImpacts() end end
  if settings and settings.grass and settings.grass.enabled ~= grassOn() then if settings.grass.enabled then startGrass() else stopGrass() end end
  if settings and tyresWanted ~= tyresOn() then if tyresWanted then startTyres() else stopTyres() end end
end

local function update(dtReal)
  retireT = retireT + dtReal
  if retireT >= 1 then retireT = 0 retireOldMod() end
  syncModules()
  if tyresOn() then carSurfaceFx_tyres.update(dtReal, wet) end
  if not settings then loadSettings() end
  local q = queue[1]
  if q then                                         -- one material reload per frame
    table.remove(queue, 1)
    setRung(q[1], q[2])
    q[1].pending = nil
  end
  glassflow.tick()
  pushScreen(dtReal)
  ensureT = ensureT + dtReal
  if ensureT > 1 then
    ensureT = 0
    for _, info in pairs(mats) do if info.glass and info.rung > 0 then canvases(info, true) end end
    local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
    local light = rules.sceneLight(type(tod) == 'table' and tod.time or tod, wet > 0.3)
    if light ~= rules.glassLight then                                -- the glints follow the light of the day: bright by day, faint at night
      rules.glassLight = light
      for _, info in pairs(mats) do if info.glass and info.mode == 'emissive' and info.rung > 0 then info.rung = -1 end end
    end
    local now = os.clock()
    for _, car in pairs(cars) do                                     -- the pane directions go to each wet glass canvas, again every 20 s (a page that was still loading drops them)
      if car.flow then
        for _, info in ipairs(car.mats) do
          local field = info.glass and info.rung > 0 and (car.flow[info.mapTo] or car.flow[info.name])
          if field and now - (car.flowAt[info.name] or -100) > 20 then
            car.flowAt[info.name] = now
            for _, msg in ipairs(glassflow.messages(field)) do car.veh:queueJSUITexture(info.tag, msg) end
          end
        end
      end
    end
  end
  timer = timer + dtReal
  if timer < 0.2 then return end
  local dt = timer
  timer = 0
  wet = forced and forced or rules.wetStep(wet, targetWet(), dt)
  wetSecs = wet > 0.1 and wetSecs + dt or math.max(0, wetSecs - dt * 0.5)
  local want = rules.level(wet, rung)
  if wet > 0 then
    for id, d in pairs(dirtBy) do dirtBy[id] = rules.dirtWash(d, dt, wet, 0, wetSecs) end        -- rain
  end
  rainT = rainT + dt
  if rainT >= 5 then
    if wet > 0.05 and scratchOn() then carSurfaceFx_scratch.washSplats(nil, rules.clamp(1 - wet * rainT / 60, 0, 1), rules.clamp(1 - wet * rainT / 420, 0, 1)) end
    rainT = 0
  end
  local pvId = be:getPlayerVehicleID(0)
  scanSpray(dt, pvId and pvId >= 0 and be:getObjectByID(pvId) or nil, wet)
  for _, id in ipairs(wantedIds()) do
    local car = cars[id]
    if not car then attach(id) car = cars[id] end
    if car then
      local mo = updateMotion(id, car.veh, dt)
      frostBy[id] = forcedFrost or (settings.weather.frost and rules.frostStep(frostBy[id] or 0, dt, airC(), engineBy[id], wet) or 0)
      if id == pvId then frostP = frostBy[id] end
      for _, info in ipairs(car.mats) do
        local w = want
        if info.glass then w = ((want > 0 or frostShown() > 0.03 or sprayShown() > 0.03 or filmOf(id) > 0.04) and settings.windscreen.windows and next(rules.glassFields(info.stages[0], info.tag, info.mode))) and 1 or 0 end
        if info.rung ~= w and not info.pending then info.pending = true queue[#queue + 1] = { info, w } end
      end
      if id == be:getPlayerVehicleID(0) then
        M.pushGlass(car, mo)
        if scratchOn() then
          local rain = forced or rules.target(nil, core_environment.getPrecipitation())
          carSurfaceFx_scratch.water(id, { rain = rain * settings.rain.intensity, wet = wet, speed = mo.speed, aLong = mo.aLong, aLat = mo.aLat, mm = settings.rain.bodyDropMm, amount = settings.rain.dropAmount, imp = settings.rain.impacts, anim = settings.rain.anim })
        end
      end
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

-- the Mods menu of Wrench Works (slrr_settings) lists our settings; it is registered at load and again when the registry says it is ready. Without Wrench Works nothing is
-- registered and the mod runs on its defaults and its json file. A leftover group of an earlier build in the game's Options page is taken out.
local OPTIONS_MARKER = 'carsurfacefx-v1'
function M.onSlrrSettingsReady()
  local S = rawget(_G, 'slrr_settings')
  if S and S.register then
    S.register(require('carSurfaceFx/schema').build(S, M))
    S.register(require('carSurfaceFx/tyresSchema').build(S, { reload = readTyresFlag }))
  end
  readTyresFlag()
end
function M.onExtensionLoaded()
  if not settings then loadSettings() end
  if rawget(_G, 'FS') then pcall(function() require('slrr/optionsLayout').uninstall(OPTIONS_MARKER) end) end
  M.onSlrrSettingsReady()
end

-- the file was changed by the Mods menu (or by hand): take it over now
function M.reloadSettings()
  if not settings then return end
  loadSettings()
  readTyresFlag()
  if scratchOn() then carSurfaceFx_scratch.configure(settings.scratch) end
end
M.onSettingsChanged = M.reloadSettings

function M.onModDeactivated() end

function M.defaults() return deepcopy(DEFAULTS) end

-- carSurfaceFx.set('scratch.colour', { r, g, b }): one value of the settings by its path, kept in the file (for the values the Mods menu cannot store as plain json)
function M.set(path, value)
  local t, key = settings, nil
  local parts = {}
  for part in tostring(path):gmatch('[^%.]+') do parts[#parts + 1] = part end
  for i = 1, #parts - 1 do t = type(t) == 'table' and t[parts[i]] or nil end
  key = parts[#parts]
  if type(t) ~= 'table' or type(t[key]) ~= type(value) then return false end
  t[key] = value
  jsonWriteFile(SETTINGS_FILE, settings, true)
  M.reloadSettings()
  return true
end
function M.getSettings() return settings end

function M.onVehicleDestroyed(id) cars[id] = nil dirtBy[id] = nil motion[id] = nil frostBy[id] = nil engineBy[id] = nil screen.forget(id) end
function M.onVehicleSpawned(id) cars[id] = nil end      -- a respawn gets new meshes and its own paint: attach again on the next update

-- everything back to how the game had it
function reset()
  if screenOn then pcall(guihooks.trigger, 'csfxScreen', { on = false }) screenOn = false end
  for _, info in pairs(mats) do if info.rung > 0 then pcall(setRung, info, 0) end end
  for id, car in pairs(cars) do
    if car.dirt and rules.dirtTotal(car.dirt) > 0 and be:getObjectByID(id) then pcall(setDirt, id, car, rules.dirtNew()) end
  end
  cars, queue, rung, wet, forced, forcedDirt, dirtBy, frostBy, engineBy, frostP = {}, {}, 0, 0, nil, nil, {}, {}, {}, 0
end
-- the level is ending: its materials, canvases and cars go with it, so nothing is reloaded or destroyed in the tick the engine takes the cars down; only our own state is dropped
function M.onClientEndMission()
  if screenOn then pcall(guihooks.trigger, 'csfxScreen', { on = false }) screenOn = false end
  for _, info in pairs(mats) do info.rung = 0 end
  cars, queue, rung, wet, forced, forcedDirt, dirtBy, frostBy, engineBy, frostP = {}, {}, 0, 0, nil, nil, {}, {}, {}, 0
end
function M.onExtensionUnloaded() reset() stopScratch() stopMarks() stopFluids() stopGrass() stopImpacts() stopRuts() if rawget(_G, 'carSurfaceFx_debug') then extensions.unload('carSurfaceFx_debug') end end

-- carSurfaceFx.debugTools(): loads the console debug set (counts, status, wheel contact markers, ground kind labels, clear all, test all); see carSurfaceFx_debug.lua
function M.debugTools()
  if not rawget(_G, 'carSurfaceFx_debug') then extensions.load('carSurfaceFx_debug') end
  return carSurfaceFx_debug.help()
end

-- carSurfaceFx.debug('rain', 1.0) / ('mud', 0.8) force a value; debug() puts the weather back
function M.debug(kind, value)
  if kind == nil then forced, forcedDirt, wiperForced, flood, forcedFrost, forcedSnowing, forcedAir, forcedSpray = nil, nil, nil, 0, nil, nil, nil, nil return 'debug cleared' end
  if kind == 'air' then forcedAir = tonumber(value) return 'air temperature forced to ' .. tostring(value) end
  if kind == 'speed' then value = tonumber(value) or 0 forcedSpeed = value > 0 and value or nil return 'the window and windscreen water sees speed ' .. tostring(forcedSpeed or "the car's own") end   -- m/s, not clamped
  value = rules.clamp(tonumber(value) or 1, 0, 1)
  if kind == 'rain' then forced = value wet = value return 'rain forced to ' .. value end
  for _, k in ipairs(rules.KINDS) do
    if kind == k then
      forcedDirt = forcedDirt or rules.dirtNew()
      local old = deepcopy(forcedDirt)
      forcedDirt[k] = value
      if k == 'snow' or k == 'bugs' then weatherSplats(be:getPlayerVehicleID(0), old, forcedDirt) end
      if k == 'mud' or k == 'dust' or k == 'rubber' or k == 'grime' then dirtSplats(be:getPlayerVehicleID(0), old, forcedDirt) end
      return k .. ' forced to ' .. value
    end
  end
  if kind == 'paintwater' then return scratchOn() and carSurfaceFx_scratch.waterDebug(value > 0) or 'scratch module is not running' end
  if kind == 'spray' then forcedSpray = value return 'spray forced to ' .. value end
  if kind == 'frost' then forcedFrost = value return 'frost forced to ' .. value end
  if kind == 'snowing' then forcedSnowing = value return 'snowfall forced to ' .. value end
  if kind == 'flood' then flood = value return 'window canvases solid: ' .. value end
  if kind == 'glassoff' then glassOff = value > 0 return 'the window canvases stay clear: ' .. tostring(glassOff) end
  if kind == 'wiper' then wiperForced = value > 0 and value or nil return 'wipers forced to ' .. value end
  return kind .. ': not built yet'
end

-- carSurfaceFx.enable('windscreen', true) turns an effect on or off for this session (the settings file is not changed)
-- carSurfaceFx.setSetting('windscreen', 'overlay', false): one value of a settings group for this session (the file is not changed); returns the old value, or nil and why
-- (used by the benchmark, carSurfaceFx_bench)
function M.setSetting(group, key, value)
  local g = settings and settings[group]
  if type(g) ~= 'table' or g[key] == nil then return nil, 'unknown setting ' .. tostring(group) .. '.' .. tostring(key) end
  local old = g[key]
  g[key] = value
  return old
end

function M.enable(effect, on)
  if not (settings and settings[effect] and type(settings[effect]) == 'table') then return 'unknown effect' end
  settings[effect].enabled = on and true or false
  for _, car in pairs(cars) do M.pushGround(car.veh) end
  return effect .. (on and ' on' or ' off')
end

-- carSurfaceFx.tuneGlass('0 1', 3.0, 0.5, 1, 0.4): (axis, drop size, colour glass tint 0..1 (lower = darker), image squaring passes 0..2, inside glint brightness) the direction that is DOWN the glass in the glass material's UV space (differs per car: '1 0', '0 -1', '-1 0' if the water runs
-- sideways or up)
function M.tuneGlass(axis, size, tint, passes, emissive, nits)
  local x, y = tostring(axis or '0 1'):match('(%-?[%d%.]+)%s+(%-?[%d%.]+)')
  if x then
    local l = math.sqrt(tonumber(x) ^ 2 + tonumber(y) ^ 2)
    if l > 0 then rules.glassAxis = { x = tonumber(x) / l, y = tonumber(y) / l } end
  end
  rules.glassSize = tonumber(size) or rules.glassSize
  rules.glassTint = tonumber(tint) or rules.glassTint
  rules.glassPasses = tonumber(passes) or rules.glassPasses
  rules.glassEmissive = tonumber(emissive) or rules.glassEmissive
  rules.glassNits = tonumber(nits) or rules.glassNits
  for _, info in pairs(mats) do if info.glass and info.mode == 'emissive' and info.rung > 0 then info.rung = -1 end end    -- the inside glass takes the new brightness at the next tick
  return string.format('glass down = %.2f %.2f, drop size %.1f, tint %.2f, passes %d, glint %.2f at %.0f nits', rules.glassAxis.x, rules.glassAxis.y, rules.glassSize, rules.glassTint, rules.glassPasses, rules.glassEmissive, rules.glassNits)
end

-- carSurfaceFx.tune('6 6', 0.6): size of the water beads (detailScale on the paint's UVs) and their strength; applied now to the wet materials
function M.tune(scale, strength)
  rules.beadScale = tostring(scale or rules.beadScale)
  rules.beadStrength = tonumber(strength) or rules.beadStrength
  for _, info in pairs(mats) do if info.rung > 0 then setRung(info, info.rung) end end
  return 'beads ' .. rules.beadScale .. ' strength ' .. rules.beadStrength
end

-- carSurfaceFx.level(id) (the player's car when nil): how dirty and scratched a car is, for a phone or garage screen
function M.level(id)
  id = id or be:getPlayerVehicleID(0)
  local d = dirtBy[id] or rules.dirtNew()
  local dirt = math.max(d.mud, d.dust * 0.7, d.grime * 0.6, d.rubber * 0.5)
  local scratches = scratchOn() and rules.clamp(carSurfaceFx_scratch.count(id) / 30, 0, 1) or 0
  return { dirt = dirt, dirtName = d.mud >= 0.3 and 'muddy' or (dirt >= 0.15 and 'dusty' or 'clean'),
    scratches = scratches, scratchName = scratches < 0.02 and 'none' or (scratches < 0.35 and 'light' or 'heavy') }
end

-- carSurfaceFx.getState(id): everything a car carries as plain numbers (json-safe), or nil when it is clean and unmarked:
-- { dirt = { dust, mud, rubber, grime }, marks = { {x1,y1,x2,y2,width} ...  at most 40 }, splats = { {x,y,r,opacity,kind} ... at most 40 } }
function M.getState(id)
  id = id or be:getPlayerVehicleID(0)
  local st = {}
  local d = dirtBy[id]
  if d and rules.dirtTotal(d) > 0 then
    st.dirt = {}
    for _, k in ipairs(rules.KINDS) do st.dirt[k] = math.floor(d[k] * 1000 + 0.5) / 1000 end
  end
  local sc = scratchOn() and carSurfaceFx_scratch.getState(id)
  if sc then st.marks, st.splats = sc.marks, sc.splats end
  return next(st) and st or nil
end

-- carSurfaceFx.setState(id, state): put a getState result back on a car (a respawned one)
function M.setState(id, st)
  if type(st) ~= 'table' then return 'no state' end
  if type(st.dirt) == 'table' then
    local d = rules.dirtNew()
    for _, k in ipairs(rules.KINDS) do d[k] = rules.clamp(tonumber(st.dirt[k]) or 0, 0, 1) end
    dirtBy[id] = d
    if cars[id] then cars[id].dirt = nil end              -- applied again at the next tick
  end
  if settings and settings.scratch.enabled and not scratchOn() then startScratch() end
  if scratchOn() then carSurfaceFx_scratch.restore(id, st) end
  return 'state set on car ' .. tostring(id)
end

-- carSurfaceFx.insideMode('color' | 'emissive') / outsideMode(...): which slot the INSIDE glass (names ending 'int') / the OUTSIDE glass takes its canvas in; rebound at the next tick
local function setGlassMode(inside, mode)
  if mode ~= 'color' and mode ~= 'emissive' then return "use 'color' or 'emissive'" end
  if inside then rules.insideMode = mode else rules.outsideMode = mode end
  for _, info in pairs(mats) do
    if info.glass and (info.name:lower():find('int$') ~= nil) == inside then
      if info.rung > 0 then canvases(info, false) end
      info.mode = mode
      if info.rung > 0 then info.rung = -1 end
    end
  end
  return (inside and 'inside' or 'outside') .. ' glass: ' .. mode
end
function M.insideMode(mode) return setGlassMode(true, mode) end
function M.outsideMode(mode) return setGlassMode(false, mode) end

-- carSurfaceFx.glassDouble(true|false): while wet, draw the outer window panes from behind too (so the cockpit sees their water); applies at the next bind
function M.glassDouble(on)
  doubleSided = on and true or false
  for _, info in pairs(mats) do if info.glass and info.mode == 'color' and info.rung > 0 then info.rung = -1 end end
  return 'outer glass double sided while wet: ' .. tostring(doubleSided)
end

-- carSurfaceFx.refreshGlass(): the windscreen's inside pane (vivace_windshield_int) is a flexbody with a material switch slot (deformMaterialBase = deformMaterialDamaged = its own
-- material, lua/common/jbeam/materials.lua), and may keep showing the material as it was when the slot was made. This asks every glass mesh of the player car to take its
-- material again through its slot, which should pick up the canvas.
function M.refreshGlass()
  local veh = getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  local n, out = 0, {}
  for _, info in pairs(mats) do
    if info.glass and info.rung > 0 then
      for mesh in string.gmatch(veh:getMeshesContainingMaterial(info.mapTo) or '', '%S+') do
        local slot = veh:getSwitchableMaterial(info.mapTo, info.mapTo, mesh)
        if slot >= 0 then veh:switchMaterial(slot, info.name) n = n + 1 end
      end
      out[#out + 1] = info.name
    end
  end
  return string.format('%d glass meshes switched again (%s)', n, table.concat(out, ', '))
end

-- carSurfaceFx.glassInfo(): the player car's window materials: which meshes use each, the slot the canvas goes in, and whether it is bound
function M.glassInfo()
  local veh = getPlayerVehicle(0)
  local out = {}
  for _, name in ipairs(veh and veh:getMaterialNames() or {}) do
    if rules.isGlassName(name) or name:lower():find('glass', 1, true) then
      local info = mats[name]
      out[#out + 1] = string.format('%s mapTo=%s mode=%s bound=%s meshes=[%s]', name, info and info.mapTo or '?', info and info.mode or '-', tostring(info and info.rung or '-'),
        veh:getMeshesContainingMaterial(info and info.mapTo or name) or '')
      if info and info.glass then
        local ok, dbg = pcall(function() return dumps(veh:getActiveUITextureDebugInfo(info.tag)) end)
        out[#out + 1] = '  canvas ' .. info.tag .. ': ' .. (ok and tostring(dbg) or ('no debug info: ' .. tostring(dbg)))
      end
    end
  end
  local car = veh and cars[veh:getID()]
  local fi = car and car.flow and car.flow._info
  out[#out + 1] = 'window flow: ' .. (fi and string.format('%d glass triangles in %d .dae file(s), %d fitted meshes of %d nodes, materials [%s], cells [%s], meshes [%s], sent %s', fi.tris, fi.files, fi.matched, fi.nodeCount, fi.wantedMats, table.concat(fi.fields, '; '), fi.meshes or '',
    car.flowAt and next(car.flowAt) and 'yes' or 'not yet') or (car and 'not built (yet, or the car has no source mesh)' or 'no car'))
  return table.concat(out, '\n')
end

-- how wet the ground is now, 0..1 (the ruts pick their wet or dry material by it)
function M.wetness() return wet end

-- carSurfaceFx.bound(): the materials of the player's car that the weather works on, and what each is (paint, trim, glass) and its wet rung
function M.bound()
  local car = cars[be:getPlayerVehicleID(0)]
  if not car then return 'no car' end
  local out = {}
  for _, info in ipairs(car.mats) do out[#out + 1] = string.format('%s [%s] r%d', info.name, info.glass and 'glass' or (info.trim and 'trim' or 'paint'), info.rung or 0) end
  return table.concat(out, ' | ')
end

function M.status()
  if failed then return 'SWITCHED OFF after: ' .. failed end
  local n, names = 0, {}
  for _ in pairs(cars) do n = n + 1 end
  for name, info in pairs(mats) do names[#names + 1] = name .. '=r' .. info.rung .. (info.glass and string.format('(%.0fms)', info.reloadMs or 0) or '') end
  local d = be:getPlayerVehicleID(0)
  local dd = forcedDirt or dirtBy[d] or rules.dirtNew()
  local rainNow = forced or rules.target(nil, core_environment.getPrecipitation())
  local extra = string.format(' wiperNow=%s snowing=%.2f flags=%s%s%s%s reports=%d (%.1fs ago) engine=%s', tostring(wipersOf(d, rainNow)), snowfall(), settings.weather.snow and 'S' or '-', settings.weather.frost and 'F' or '-',
    settings.weather.bugs and 'B' or '-', settings.weather.spray and 'P' or '-', groundCalls, os.clock() - groundAt, tostring(engineBy[d]))
  return extra .. string.format(' | wet %.2f rung %d forced %s dirt dust %.2f mud %.2f rubber %.2f grime %.2f snow %.2f bugs %.2f frost %.2f spray %.2f air %s (forced %s) cars %d queue %d wiper=%s motion=%s materials [%s]', wet, rung, tostring(forced), dd.dust, dd.mud, dd.rubber, dd.grime, dd.snow, dd.bugs, frostBy[d] or 0, sprayP, tostring(airC()), tostring(forcedDirt ~= nil), n, #queue, tostring(wiperBy[d]), motion[d] and string.format('v%.1f aL%.1f aT%.1f', motion[d].speed, motion[d].aLong, motion[d].aLat) or '-', table.concat(names, ' '))
end

return M
