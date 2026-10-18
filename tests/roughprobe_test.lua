-- carSurfaceFx/roughProbe.lua against a mocked game: the paint layers are found, the canvas is bound to the slot, the clear coat can be switched off, restore puts it all back.
local function material(name, fields)
  local m = { fields = fields }
  function m:getField(k, layer) return (self.fields[layer] or {})[k] end
  function m:setField(k, layer, v) self.fields[layer] = self.fields[layer] or {} self.fields[layer][k] = v end
  function m:getClassName() return 'Material' end
  function m:reload() self.reloads = (self.reloads or 0) + 1 end
  return m
end
local paint = material('body', { [0] = { translucent = '0', activeLayers = '1', instanceDiffuse = '1', roughnessMap = '', roughnessFactor = '0.9', clearCoatFactor = '1', metallicFactor = '0.4' } })
local glass = material('glass', { [0] = { translucent = '1', activeLayers = '1' } })
local plastic = material('trim', { [0] = { translucent = '0', activeLayers = '1', instanceDiffuse = '0' } })
local byName = { body = paint, glass = glass, trim = plastic }
scenetree = { findObject = function(n) return byName[n] end }
UI_TEXTURE_USAGE_AUTOMATIC = 1
local textures = {}
local veh = { getID = function() return 4 end, getMaterialNames = function() return { 'body', 'glass', 'trim' } end,
  createUITexture = function(_, tag, page, w, h, usage, fps) textures[tag] = { page = page, w = w, h = h } end,
  destroyUITexture = function(_, tag) textures[tag] = nil end }
getPlayerVehicle = function() return veh end
getObjectByID = function() return veh end
local P = dofile('mod/lua/ge/extensions/carSurfaceFx/roughProbe.lua')
local info = P.info()
assert(info:find('body L0', 1, true) and not info:find('glass', 1, true) and not info:find('trim', 1, true), 'only the paint layer is listed: ' .. info)
assert(P.run():find('1 paint layer', 1, true), 'run')
assert(paint.fields[0].roughnessMap == '@csfx_probe' and paint.reloads == 1, 'the canvas tag is in the roughness slot, reloaded')
assert(textures['@csfx_probe'] and textures['@csfx_probe'].page:find('probe.html?m=grid', 1, true) and textures['@csfx_probe'].w == 1024, 'the canvas was made')
assert(P.noCoat():find('without clear coat', 1, true) and paint.fields[0].clearCoatFactor == '0', 'the clear coat is off')
assert(P.restore():find('1 layer', 1, true), 'restore')
assert(paint.fields[0].roughnessMap == '' and paint.fields[0].clearCoatFactor == '1' and textures['@csfx_probe'] == nil, 'everything as it was')
assert(P.run('metallicMap'):find('metallicMap', 1, true) and paint.fields[0].metallicMap == '@csfx_probe', 'the metallic slot too')
P.restore()
assert(paint.fields[0].metallicMap == nil or paint.fields[0].metallicMap == '', 'metallic put back')
print('carSurfaceFx rough probe: ok')
