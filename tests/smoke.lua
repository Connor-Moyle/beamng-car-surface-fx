-- Runs the extension against a mocked game for a few hundred ticks: rain on, a car that brakes and corners, wipers, mud, a respawn, unload.
-- Catches runtime errors (nil fields, wrong calls) that the pure-rules tests cannot see. Mock methods mirror what the game's API gave in the spikes.
local logs, fields, reloads, paintCalls = {}, {}, 0, 0
function log(level, tag, msg) logs[#logs + 1] = level .. ' ' .. tag .. ' ' .. msg end
function deepcopy(t) if type(t) ~= 'table' then return t end local c = {} for k, v in pairs(t) do c[k] = deepcopy(v) end return c end
function jsonReadFile() return { mud = { buildup = true } } end
function jsonWriteFile() end
function jsonEncode(t) local o = {} for k, v in pairs(t) do o[#o + 1] = k .. '=' .. tostring(v) end table.sort(o) return '{' .. table.concat(o, ',') .. '}' end
UI_TEXTURE_USAGE_AUTOMATIC = 0

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
  vivace_glass = material('vivace_glass', true, { [0] = {} }, 'vivace_glass'),
  vivace_wheel = material('vivace_wheel', false, { [0] = { colorPaletteMap = '/null.png' } }),
  licenseplate = material('licenseplate', false, { [0] = { colorPaletteMap = '/null.png' } }),
}
local meshes = { vivace = 35, vivace_glass = 6, vivace_wheel = 4, licenseplate = 1 }
scenetree = { findObject = function(n) return mats[n] end }
Sim = { upcast = function(o) return o end }

local v = { vx = 0, vy = 0 }
local car = { id = 7, resets = 0, switches = 0 }
function car:getID() return self.id end
function car:getMaterialNames() return { 'vivace_main', 'vivace_glass', 'vivace_wheel', 'licenseplate' } end
function car:getMeshesContainingMaterial(mapTo) return string.rep('m ', meshes[mapTo] or 0) end
function car:getVelocity() return { x = v.vx, y = v.vy, z = 0 } end
function car:getDirectionVector() return { x = 1, y = 0, z = 0 } end
function car:queueLuaCommand() end
function car:resetMaterials() end
local tags, js, order = {}, {}, {}
function car:getActiveUITextureTagNames() local t = {} for k in pairs(tags) do t[#t + 1] = k end return t end
function car:createUITexture(tag) tags[tag] = true order[#order + 1] = 'canvas' end
function car:destroyUITexture(tag) tags[tag] = nil order[#order + 1] = 'destroy' end
function car:queueJSUITexture(tag, code) js[#js + 1] = code end
function car:switchMaterial() end
local alive = true
be = {
  getObjectByID = function(_, id) return alive and car or nil end,
  getPlayerVehicle = function() return car end,
  getPlayerVehicleID = function() return 7 end,
  getObjectCount = function() return 1 end,
  getObject = function() return car end,
}
core_environment = { getPrecipitation = function() return 600 end, groundModels = { MUD = { cdata = { collisiontype = 14 } } } }
core_vehicle_manager = { getVehicleData = function() return { config = { paints = { { baseColor = { 0.4, 0.6, 0.1, 1 }, metallic = 0.8, roughness = 0.6, clearcoat = 1, clearcoatRoughness = 0.1 } } } } end,
  liveUpdateVehicleColors = function() paintCalls = paintCalls + 1 end }
core_camera = { getActiveCamName = function() return 'driver' end }

local M = dofile('mod/lua/ge/extensions/carSurfaceFx.lua')
local function tick(n, dt) for _ = 1, n do M.onUpdate(dt or 0.25) end end

M.debug('rain', 1.0)
tick(40)                                                  -- rain climbs, glass and paint get their rungs, one reload per tick
assert(mats.vivace_main.fields[0].detailNormalMap:find('droplets', 1, true), 'paint got its beads')
assert(mats.vivace_glass.fields[0].detailNormalMap == '@csfx_glass', 'glass is bound to the water canvas')
assert(tags['@csfx_glass'], 'the car has the canvas')
assert(#js > 0 and js[#js]:find('csfxSet', 1, true), 'the canvas gets the weather: ' .. tostring(js[#js]))
assert(mats.vivace_wheel.fields[0].detailNormalMap == nil, 'wheel left alone')
assert(mats.licenseplate.fields[0].detailNormalMap == nil, 'plate left alone')
v.vx = 20 tick(8) v.vx = 0 tick(8)                        -- accelerate, brake hard
M.debug('wiper', 1) tick(10)
assert(js[#js]:find('wiper=1', 1, true), 'the wipers reach the canvas: ' .. js[#js])
M.debug('wiper', 0) tick(10)
M.debug('mud', 0.8) tick(5)
M.onVehicleSpawned(7) tick(10)                            -- respawn: attaches again
M.debug() tick(5)
for _ = 1, 60 do M.onGround(7, 1, 0, 0, 0, 0, 20, 0.5, 0) tick(2) end   -- a minute on a dirt road in the rain: mud
assert(M.status():find('mud 0%.[1-9]') or M.status():find('mud 1'), 'mud built: ' .. M.status())
assert(paintCalls > 0, 'the paint was updated')
for _ = 1, 40 do M.onGround(7, 0, 0, 0, 0, 1, 5, 0.5, 0) tick(2) end   -- then through a river: washed
assert(M.status():find('dust 0%.00 mud 0%.00'), 'water washed it: ' .. M.status())
M.onGround(7, 0, 0, 1, 1, 0, 20, 0.5, 0)
M.wash()
tick(3)
M.debug() tick(400)                                       -- the weather decides (600 drops): still wet, no error
assert(not M.status():find('SWITCHED OFF'), 'no error: ' .. M.status() .. ' ' .. table.concat(logs, ' | '))
M.onExtensionUnloaded()
assert(mats.vivace_main.fields[0].detailNormalMap == '/peel.png', 'the original orange peel is back: ' .. tostring(mats.vivace_main.fields[0].detailNormalMap))
assert(mats.vivace_main.fields[0].detailScale == '128 64', 'the original detail scale is back')
assert(mats.vivace_glass.fields[0].detailNormalMap == '', 'the glass is unbound')
assert(not tags['@csfx_glass'], 'the canvas is gone')
assert(order[1] == 'canvas', 'the canvas existed before the material pointed at it')
for _, l in ipairs(logs) do assert(not l:find('^E'), l) end
print('carSurfaceFx smoke: ok, ' .. reloads .. ' reloads over the run')
