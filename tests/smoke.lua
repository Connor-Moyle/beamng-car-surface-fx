-- Runs the extension against a mocked game for a few hundred ticks: rain on, a car that brakes and corners, wipers, mud, a respawn, unload.
vec3 = vec3 or function(x, y, z) return { x = x, y = y, z = z } end
quat = quat or function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
-- Catches runtime errors (nil fields, wrong calls) that the pure-rules tests cannot see. Mock methods mirror what the game's API gave in the spikes.
local logs, fields, reloads, paintCalls = {}, {}, 0, 0
function log(level, tag, msg) logs[#logs + 1] = level .. ' ' .. tag .. ' ' .. msg end
function deepcopy(t) if type(t) ~= 'table' then return t end local c = {} for k, v in pairs(t) do c[k] = deepcopy(v) end return c end
fileData = { mud = { buildup = true } }
function jsonReadFile() return fileData end
function jsonWriteFile() end
function jsonEncode(t) local o = {} for k, v in pairs(t) do o[#o + 1] = k .. '=' .. tostring(v) end table.sort(o) return '{' .. table.concat(o, ',') .. '}' end
UI_TEXTURE_USAGE_AUTOMATIC = 0
local waterCalls, lastWater = 0, nil
local bodySplats = {}
local splats, started, repaired, washes, repairedId, restoredId, restored = 0, {}, 0, 0, nil, nil, nil
extensions = {
  load = function(n) started[#started + 1] = n _G[n] = { configure = function() end, noteGround = function() end, splat = function(_, _, _, k) splats = splats + k end, buffOut = function() end, water = function(id, p) waterCalls = waterCalls + 1 lastWater = p end, repair = function(id) repaired = repaired + 1 repairedId = id end, count = function() return 12 end,
    getState = function() return { marks = { { 0.1, 0.1, 0.2, 0.2, 0.002 } }, splats = {} } end, restore = function(id, st) restoredId, restored = id, st end,
    washSplats = function() washes = washes + 1 end, dirtAt = function() return false end, bodySplat = function(_, region, _, _, k) bodySplats[region] = (bodySplats[region] or 0) + k end } end,
  unload = function(n) _G[n] = nil end,
}
function setExtensionUnloadMode() end
local unloaded = {}
extensions.unload = function(n) unloaded[#unloaded + 1] = n _G[n] = nil end
function getAllVehicles() return {} end
guihooks = guihooks or {}

local function material(name, glass, stages, mapTo)
  local m = { name = name, fields = {} }
  for L = 0, 3 do m.fields[L] = {} for k, v in pairs(stages[L] or {}) do m.fields[L][k] = v end end
  m.fields[0].mapTo, m.fields[0].version, m.fields[0].translucent = mapTo or name, '1.5', glass and '1' or '0'
  function m:getField(k, L) return (self.fields[L] or {})[k] or '' end
  function m:setField(k, L, v) self.fields[L] = self.fields[L] or {} self.fields[L][k] = v end
  function m:getFilename() return 'x.json' end
  function m:reload() reloads = reloads + 1 end
  return m
end
local mats = {
  vivace_main = material('vivace_main', false, { [0] = { colorPaletteMap = '/null.png', clearCoatFactor = '1', detailNormalMap = '/peel.png', detailScale = '128 64' }, [1] = { baseColorMap = '/b.png' } }, 'vivace'),
  vivace_glass = material('vivace_glass', true, { [0] = { baseColorMap = 'vehicles/vivace/vivace_glass_b.color.png' } }, 'vivace_glass'),
  vivace_glass_int = material('vivace_glass_int', true, { [0] = { baseColorMap = '/b.png', opacityMap = '/vehicles/vivace/vivace_glass_o.data.png' } }, 'vivace_glass_int'),
  vivace_wheel = material('vivace_wheel', false, { [0] = { colorPaletteMap = '/null.png' } }),
  licenseplate = material('licenseplate', false, { [0] = { colorPaletteMap = '/null.png' } }),
}
local meshes = { vivace = 35, vivace_glass = 6, vivace_wheel = 4, licenseplate = 1 }
scenetree = { findObject = function(n) return mats[n] end }
Sim = { upcast = function(o) return o end }

local v = { vx = 0, vy = 0 }
local car = { id = 7, resets = 0, switches = 0 }
function car:getID() return self.id end
function car:getMaterialNames() return { 'vivace_main', 'vivace_glass', 'vivace_glass_int', 'vivace_wheel', 'licenseplate' } end
function car:getMeshesContainingMaterial(mapTo) return string.rep('m ', meshes[mapTo] or 0) end
function car:getVelocity() return { x = v.vx, y = v.vy, z = 0 } end
function car:getDirectionVector() return { x = 1, y = 0, z = 0 } end
function car:queueLuaCommand() end
function car:getPosition() return { x = 0, y = 0, z = 0 } end
local corners = { { -0.6, 0, 0 }, { 0.6, 0, 0 }, { 0.5, 0, 0.5 }, { -0.5, 0, 0.5 } }
function car:getNodePosition(cid) local c = corners[cid] or corners[1] return { x = c[1], y = 2, z = c[3] } end
function car:resetMaterials() end
local tags, js, order = {}, {}, {}
function car:getActiveUITextureTagNames() local t = {} for k in pairs(tags) do t[#t + 1] = k end return t end
function car:createUITexture(tag) tags[tag] = true order[#order + 1] = 'canvas' end
function car:destroyUITexture(tag) tags[tag] = nil order[#order + 1] = 'destroy' end
function car:queueJSUITexture(tag, code) js[#js + 1] = code end
function car:switchMaterial() end
local alive = true
local lead                                   -- a second car ahead, set by the spray test
be = {
  getObjectByID = function(_, id) return alive and car or nil end,
  getPlayerVehicle = function() return car end,
  getPlayerVehicleID = function() return 7 end,
  getObjectCount = function() return lead and 2 or 1 end,
  getObject = function(_, i) if i == 1 then return lead end return car end,
}
core_environment = { getPrecipitation = function() return 600 end, getTemperatureK = function() return 288 end, groundModels = { MUD = { cdata = { collisiontype = 14 } } } }
core_vehicle_manager = { getVehicleData = function() return { vdata = { flexbodies = { { mesh = 'vivace_windshield', ['_group_nodes'] = { 1, 2, 3, 4 } }, { mesh = 'vivace_windshield_int', ['_group_nodes'] = { 5, 6, 7 } } } }, config = { paints = { { baseColor = { 0.4, 0.6, 0.1, 1 }, metallic = 0.8, roughness = 0.6, clearcoat = 1, clearcoatRoughness = 0.1 } } } } end,
  liveUpdateVehicleColors = function() paintCalls = paintCalls + 1 end }
camName = 'driver'
core_camera = { getActiveCamName = function() return camName end }
local gh = {}
guihooks = { trigger = function(n, d) gh[#gh + 1] = { n, d } end }
require('carSurfaceFx/screen').camera = function() return { x = 0, y = 0, z = 0.25, r = { x = 1, y = 0, z = 0 }, f = { x = 0, y = 1, z = 0 }, u = { x = 0, y = 0, z = 1 }, halfTan = 0.8, aspect = 1.7 } end

require('carSurfaceFx/rules').outsideMode = 'color'                -- these checks look at the colour slot (the default is the emissive slot: the glass keeps its own colour)
local M = dofile('mod/lua/ge/extensions/carSurfaceFx.lua')
local function tick(n, dt) for _ = 1, n do M.onUpdate(dt or 0.25) end end

local gameValues = {}
settings = { getValue = function(k) return gameValues[k] end, setValue = function(k, v) gameValues[k] = v end }   -- the game's own settings module
M.debug('rain', 1.0)
tick(40)
fileData = { mud = { buildup = true, rate = 1.5 }, scratch = { markSize = 2 }, windscreen = { enabled = false } }
M.reloadSettings()
assert(M.getSettings().mud.buildup and M.getSettings().mud.rate == 1.5 and M.getSettings().scratch.markSize == 2 and not M.getSettings().windscreen.enabled, 'a change of the settings file is taken over at once')
fileData = { mud = { buildup = true }, windscreen = { windows = true }, weather = { snow = true, frost = true, bugs = true, spray = true }, impacts = { enabled = true } }   -- the features that ship off, on for the test
M.reloadSettings()                                                     -- rain climbs, glass and paint get their rungs, one reload per tick
tick(40)
assert(mats.vivace_main.fields[0].detailNormalMap:find('droplets', 1, true), 'paint got its beads')
assert(mats.vivace_glass.fields[0].baseColorMap == '@csfx_vivace_glass', 'glass is bound to the water canvas')
assert(tags['@csfx_vivace_glass'], 'the car has the canvas')
assert(mats.vivace_glass_int.fields[0].emissiveMap == '@csfx_vivace_glass_int' and mats.vivace_glass_int.fields[0].baseColorMap == '/b.png', 'inside glass: emissive map is the canvas, tint kept')
assert(#js > 0 and js[#js]:find('csfxSet', 1, true), 'the canvas gets the weather: ' .. tostring(js[#js]))
assert(tostring(mats.vivace_wheel.fields[0].detailNormalMap):find('droplets', 1, true), 'the wheel is part of the outside and gets wet too')
assert(mats.licenseplate.fields[0].detailNormalMap == nil, 'plate left alone')
v.vx = 20 tick(8) v.vx = 0 tick(8)                        -- accelerate, brake hard
M.debug('wiper', 1) tick(10)
local lastGh = gh[#gh]
assert(lastGh and lastGh[1] == 'csfxScreen' and lastGh[2].on and #lastGh[2].hull >= 6 and lastGh[2].wiper == 1, 'the overlay of the driver view gets its outline and the wipers')
camName = 'orbit' tick(5)
assert(gh[#gh][2].on == false, 'the overlay is switched off in another camera')
camName = 'driver'
assert(js[#js]:find('wiper=1', 1, true), 'the wipers reach the canvas: ' .. js[#js])
M.debug('wiper', 0) tick(10)
M.debug('rain', 1) M.onGround(7, 0, 0, 0, 0, 0, 5, 0.5, -1) tick(10)
assert(js[#js]:find('wiper=1', 1, true), 'a car with no wiper value gets wipers by the rain: ' .. js[#js])
M.onGround(7, 0, 0, 0, 0, 0, 5, 0.5, 0.0) tick(10)
assert(js[#js]:find('wiper=0', 1, true), 'its own wipers off: ' .. js[#js])
M.onGround(7, 0, 0, 0, 0, 0, 5, 0.5, 1) tick(10)
assert(js[#js]:find('wiper=1', 1, true), 'its own wipers on: ' .. js[#js])
M.debug('mud', 0.8) tick(5)
M.onVehicleSpawned(7) tick(10)                            -- respawn: attaches again
M.debug() tick(5)
for _ = 1, 60 do M.onGround(7, 1, 0, 0, 0, 0, 20, 0.5, 0) tick(2) end   -- a minute on a dirt road in the rain: mud
assert(M.status():find('mud 0%.[1-9]') or M.status():find('mud 1'), 'mud built: ' .. M.status())
assert(paintCalls > 0, 'the paint was updated')
assert(started[1] == 'carSurfaceFx_meshuv' and started[2] == 'carSurfaceFx_scratch', 'the scratch module started, map first')
local grassStarted = false
for _, n in ipairs(started) do if n == 'carSurfaceFx_grass' then grassStarted = true end end
assert(not grassStarted, 'the grass module stays off by default (not proven in game)')
assert(splats > 0, 'dirt splats were asked for on loose ground')
assert(waterCalls > 0 and lastWater.rain >= 0 and lastWater.speed ~= nil, 'the paint water gets the weather and the motion')
for _ = 1, 40 do M.onGround(7, 0, 0, 0, 0, 1, 5, 0.5, 0) tick(2) end   -- then through a river: washed
assert(M.status():find('dust 0%.00 mud 0%.00'), 'water washed it: ' .. M.status())
-- slush: debug('groundsnow') makes the wheels run on snow, and a drive throws slush (the mocked scratch refuses it; the counters still count the calls)
M.debug('groundsnow', 1)
for _ = 1, 5 do M.onGround(7, 0, 0, 0, 0, 0, 16, 0.5, 0) end
assert(M.snowStatus():find('slush calls [1-9]'), 'slush is asked for on forced snow ground: ' .. M.snowStatus())
M.debug()
local before = M.snowStatus()
M.onGround(7, 0, 0, 0, 0, 0, 16, 0.5, 0)
assert(M.snowStatus() == before, 'no snow ground, no slush')
M.onGround(7, 0, 0, 1, 1, 0, 20, 0.5, 0)
M.wash()
tick(3)
assert(washes > 0, 'washing reaches the splats')
M.repair()
assert(repaired == 1 and repairedId == 7, 'repair reaches the scratches, of the player car by default')
M.repair(9)
assert(repairedId == 9, 'repair of one car by id')
assert(M.apiVersion == 2, 'api version')
local lv = M.level(7)
assert(lv.scratchName == 'heavy' and (lv.dirtName == 'clean' or lv.dirtName == 'dusty' or lv.dirtName == 'muddy'), 'level names: ' .. lv.dirtName .. ' ' .. lv.scratchName)
M.setState(5, { dirt = { dust = 0.2, mud = 0.8, rubber = 0, grime = 0.1 }, marks = { { 0.1, 0.1, 0.2, 0.2, 0.002 } }, splats = {} })
assert(restoredId == 5 and #restored.marks == 1, 'setState hands the marks to the scratch module')
local gs = M.getState(5)
assert(gs.dirt.mud == 0.8 and gs.marks and #gs.marks == 1, 'getState gives back what was set')
assert(M.level(5).dirtName == 'muddy', 'a muddy car is muddy')
assert(M.getState(6) == nil or M.getState(6).dirt == nil, 'a car with nothing has no dirt state')

-- spray from a car ahead
lead = { getID = function() return 8 end, getPosition = function() return { x = 0, y = 12, z = 0 } end, getDirectionVector = function() return { x = 0, y = 1, z = 0 } end,
  getVelocity = function() return { x = 0, y = 25, z = 0 } end, getInitialLength = function() return 12 end, getMaterialNames = function() return {} end,
  getActiveUITextureTagNames = function() return {} end, getMeshesContainingMaterial = function() return '' end }
car.getDirectionVector = function() return { x = 0, y = 1, z = 0 } end
M.debug('rain', 1) tick(20)
assert(M.status():find('spray 0%.[1-9]') or M.status():find('spray 1'), 'a truck 12 m ahead sprays the windscreen: ' .. M.status())
assert(js[#js]:find('spray=', 1, true), 'spray reaches the window canvas')
lead = nil tick(40)
assert(M.status():find('spray 0%.00'), 'the spray fades when it is gone: ' .. M.status())
car.getDirectionVector = function() return { x = 1, y = 0, z = 0 } end
M.debug()

-- forced snow and bugs show in status and put their splats on the body
bodySplats = {}
M.debug('snow', 0.9) M.debug('bugs', 1)
assert(M.status():find('snow 0%.90') and M.status():find('bugs 1%.00'), 'forced amounts are in the status: ' .. M.status())
assert((bodySplats.top or 0) > 0 and (bodySplats.front or 0) > 0, 'forced snow and bugs put splats on the roof and the nose')
assert(M.status():find('wiperNow=') and M.status():find('reports='), 'the status says what the wipers and the wheel reports are doing')
M.debug()

-- splash from a puddle: left wheels in water at speed
M.debug() tick(10)
bodySplats = {}
M.onGround(7, 0, 0, 1, 0, 1, 22, 0.5, 0, 20, 1, 0)
assert((bodySplats.lowL or 0) > 0 and (bodySplats.lowR or 0) == 0, 'splash on the left side only: ' .. tostring(bodySplats.lowL) .. ' ' .. tostring(bodySplats.lowR))
M.onGround(7, 0, 0, 1, 0, 1, 25, 0.5, 0, 20, 1, 1)
tick(1, 0.25)
assert(M.status():find('spray 0%.[1-9]'), 'a deep puddle at speed throws a sheet over the windscreen: ' .. M.status())
tick(30)
assert(M.status():find('spray 0%.00'), 'and it runs off: ' .. M.status())
bodySplats = {}
M.onGround(7, 0, 0, 1, 0, 1, 6, 0.5, 0, 20, 1, 1)
assert(next(bodySplats) == nil, 'slow through a puddle: no splash')

-- snow, frost, bugs
M.debug() tick(5)
M.debug('rain', 0)  tick(10)
M.debug('air', -4) M.debug('snowing', 1)
for _ = 1, 400 do M.onGround(7, 0, 0, 0, 0, 0, 0, 0.5, 0, -4) end  -- 400 reports: heavy snow now takes 180 s to coat a car (200 reports left it at 0.56)
assert(M.status():find('snow 1%.00'), 'a standing car under snow gets a coat: ' .. M.status())
assert((bodySplats.top or 0) > 0, 'snow splats went on the roof')
for _ = 1, 40 do M.onGround(7, 0, 0, 1, 0, 0, 30, 0.5, 0, -4) end
assert(M.status():find('snow 0%.00'), 'driving blew it off: ' .. M.status())
M.debug('snowing', 0) M.debug('air', 22)           -- insects fly in warm air only
for _ = 1, 400 do M.onGround(7, 0, 0, 1, 0, 0, 38, 0.5, 0, -4) end
assert((bodySplats.front or 0) > 0 and M.status():find('bugs 0%.[1-9]'), 'bugs gathered on the nose: ' .. M.status())
M.debug('air', -6)
tick(1500)
assert(M.status():find('frost 1%.00'), 'a cold night froze the glass: ' .. M.status())
assert(mats.vivace_glass.fields[0].baseColorMap == '@csfx_vivace_glass' or tags['@csfx_vivace_glass'], 'frost binds the glass canvas even without rain')
M.onGround(7, 0, 0, 0, 0, 0, 0, 0.5, 0, 85)
tick(1200)
assert(M.status():find('frost 0%.00'), 'a warm engine cleared it: ' .. M.status())
M.debug()
-- the Mods menu schema: registered with the registry, every field complete and consistent with the mod's defaults
local registered
slrr_settings = {
  register = function(sc) registered = registered or sc end,          -- (the first page is the mod's own; the Tyres page registers after it)
  each = function(ids, fn) local out = {} for _, id in ipairs(ids) do for _, f in ipairs(fn(id)) do out[#out + 1] = f end end return out end,
  join = function(...) local out = {} for _, l in ipairs({ ... }) do for _, f in ipairs(l) do out[#out + 1] = f end end return out end,
}
M.onSlrrSettingsReady()
assert(registered and registered.mod == 'car_surface_fx', 'the mod registers itself with the Mods menu')
local tabIds, seen, TYPES = {}, {}, { heading = 1, note = 1, bool = 1, slider = 1, int = 1, enum = 1, color = 1, texture = 1, button = 1, text = 1 }
for _, t in ipairs(registered.tabs) do tabIds[t.id] = true assert(t.title and t.description, 'tab ' .. t.id .. ' has a title and a description') end
assert(#registered.fields > 100, 'every setting is a field: ' .. #registered.fields)
for _, f in ipairs(registered.fields) do
  assert(f.id and not seen[f.id], 'unique field id ' .. tostring(f.id)) seen[f.id] = true
  assert(tabIds[f.tab], f.id .. ': tab exists')
  assert(TYPES[f.type], f.id .. ': known type ' .. tostring(f.type))
  assert(f.label and #f.label > 2 and f.tooltip and #f.tooltip > 10, f.id .. ': label and tooltip')
  assert(f.group, f.id .. ': in a group')
  if f.type ~= 'button' then
    assert(f.default ~= nil and f.store, f.id .. ': default and store')
    if f.type == 'slider' or f.type == 'int' then
      assert(type(f.default) == 'number' and f.default >= f.min and f.default <= f.max, f.id .. ': default ' .. tostring(f.default) .. ' within ' .. f.min .. '..' .. f.max)
    end
    if f.store.kind == 'json' then
      local t = M.defaults()
      for part in f.store.path:gmatch('[^%.]+') do t = t[part] end
      assert(t == f.default, f.id .. ': default matches the default of the mod')
    else
      assert(f.store.get and f.store.set, f.id .. ': custom store has get and set')
      local got = f.store.get()
      assert(got ~= nil, f.id .. ': get answers without the module running')
      if f.type == 'color' then assert(got.r and got.g and got.b and f.default.r == got.r, f.id .. ': colour default') end
      if f.type ~= 'color' then assert(got == f.default, f.id .. ': default matches ' .. tostring(got) .. ' ~= ' .. tostring(f.default)) end
    end
  end
end
local nPresets = 0
for _, f in ipairs(registered.fields) do
  if f.presets then
    nPresets = nPresets + 1
    assert(not tostring(f.id):lower():find('tyre', 1, true) and not tostring(f.id):lower():find('tire', 1, true), f.id .. ': no Quick setup level touches a tyre value (the tyre simulation ships off)')
    for _, level in ipairs({ 'performance', 'balanced', 'quality', 'max' }) do
      local v = f.presets[level]
      assert(v ~= nil and type(v) == type(f.default), f.id .. ': preset ' .. level .. ' has the type of the field')
      if type(v) == 'number' then assert(v >= f.min and v <= f.max, f.id .. ': preset ' .. level .. ' ' .. tostring(v) .. ' within ' .. f.min .. '..' .. f.max) end
    end
  end
end
for _, f in ipairs(registered.fields) do
  if f.type == 'bool' then
    local isTest = tostring(f.label):find('(test)', 1, true) ~= nil
    assert((f.feature == true) ~= isTest, f.id .. ': an on/off switch is tagged as a feature, a switch labelled (test) is not')
  end
end
assert(nPresets >= 12, 'the frame-costing settings have presets: ' .. nPresets)
-- coverage: every value of the mod's defaults has a field in the Mods menu, or is listed here as one that is not a setting for players
do
  local covered = {}
  for _, f in ipairs(registered.fields) do
    local st = f.store
    if st and st.path then covered[(st.module or 'main') .. ':' .. st.path] = true end
  end
  local function isColour(t) return #t == 3 and type(t[1]) == 'number' and type(t[2]) == 'number' and type(t[3]) == 'number' end
  local function walk(module, t, prefix, out)
    for k, v in pairs(t) do
      local path = prefix == '' and tostring(k) or (prefix .. '.' .. tostring(k))
      if type(v) == 'table' and not isColour(v) and next(v) ~= nil and v[1] == nil then walk(module, v, path, out)
      else out[#out + 1] = module .. ':' .. path end
    end
  end
  local all = {}
  walk('main', M.defaults(), '', all)
  walk('marks', require('carSurfaceFx/marks').defaults(), '', all)
  walk('ruts', require('carSurfaceFx/rutrules').defaults(), '', all)
  walk('impacts', require('carSurfaceFx/impactrules').defaults(), '', all)
  walk('fluids', require('carSurfaceFx/fluidrules').defaults(), '', all)
  table.sort(all)
  local NOT_SETTINGS = { ['main:settingsVersion'] = true }       -- a file version
  local missing = {}
  for _, key in ipairs(all) do if not covered[key] and not NOT_SETTINGS[key] and not key:match(':enabled$') then missing[#missing + 1] = key end end
  assert(#missing == 0, 'every value of the mod has a field in the Mods menu; without: ' .. table.concat(missing, ', '))
end
assert(seen.dirt_build and seen.takeover and seen.dirt_skid_w and seen.mud_skid_tex, 'the surfaces and the main tabs are there')
slrr_settings = nil

-- the old Surface FX mod loaded as well: switched off, the player told once, ours keeps running
local told = 0
guihooks.message = function() told = told + 1 end
surfaceFXBody = {} dirtSkidManager = {}
tick(8)
local gone = {}
for _, n in ipairs(unloaded) do gone[n] = true end
assert(gone.surfaceFXBody and gone.dirtSkidManager and rawget(_G, 'dirtSkidManager') == nil, 'the old mod was unloaded (our own surfaceFXBody takes its name back)')
surfaceFXBody = { csfxShim = true }
unloaded = {}
tick(8)
assert(#unloaded == 0, 'our compatibility modules are not taken for the old mod')
assert(told == 1, 'the player is told once: ' .. told)
surfaceFXBody = {}
tick(8)
assert(told == 1, 'and not again')
assert(M.status() and not M.status():find('SWITCHED OFF'), 'Car Surface FX keeps running')
local hasMarks = false
for _, n in ipairs(started) do if n == 'carSurfaceFx_marks' then hasMarks = true end end
assert(hasMarks, 'the marks module started')
M.debug() tick(400)                                       -- the weather decides (600 drops): still wet, no error
assert(not M.status():find('SWITCHED OFF'), 'no error: ' .. M.status() .. ' ' .. table.concat(logs, ' | '))
M.onExtensionUnloaded()
assert(rawget(_G, 'carSurfaceFx_scratch') == nil, 'the scratch module is unloaded with the mod')
assert(rawget(_G, 'carSurfaceFx_grass') == nil, 'the grass module is unloaded with the mod')
assert(mats.vivace_main.fields[0].detailNormalMap == '/peel.png', 'the original orange peel is back: ' .. tostring(mats.vivace_main.fields[0].detailNormalMap))
assert(mats.vivace_main.fields[0].detailScale == '128 64', 'the original detail scale is back')
assert(mats.vivace_glass.fields[0].baseColorMap == 'vehicles/vivace/vivace_glass_b.color.png', 'the glass has its own tint map back')
assert(not tags['@csfx_vivace_glass'], 'the canvas is gone')
assert(order[1] == 'canvas', 'the canvas existed before the material pointed at it')
for _, l in ipairs(logs) do assert(not l:find('^E'), l) end
print('carSurfaceFx smoke: ok, ' .. reloads .. ' reloads over the run')
