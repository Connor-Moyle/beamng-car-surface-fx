-- Car Surface FX: does the paint material read a web canvas in its roughness (or metallic) slot, and does it show under the clear coat? A test, not part of the mod (nothing
-- loads it). Water drops drawn as glossy spots (low roughness) would give a real highlight; this finds out whether that is possible.
--   extensions.load('carSurfaceFx_roughProbe')
--   carSurfaceFx_roughProbe.info()               -- the player's paint layers and their roughness, metallic and clear coat fields now
--   carSurfaceFx_roughProbe.run()                -- binds a canvas (white, with black discs, a black band and a black-to-white bar) to the roughnessMap of those layers
--   carSurfaceFx_roughProbe.run('metallicMap')   -- the same on the metallic slot
--   carSurfaceFx_roughProbe.noCoat()             -- also switches the clear coat of those layers off (to see whether it hides the slot); restore() puts it back
--   carSurfaceFx_roughProbe.restore()            -- everything as it was
-- Black reads as 0 (glossy / not metal), white as 1 (rough / metal). If the discs show as mirror-like spots against matte paint, or the bar as a gradient of gloss, the slot works.
local M = {}

local TAG = '@csfx_probe'
local PAGE = 'local://local/vehicles/common/carSurfaceFx/probe.html'
local PAGE_V = 1
local KEYS = { 'roughnessMap', 'roughnessFactor', 'metallicMap', 'metallicFactor', 'clearCoatFactor', 'clearCoatRoughnessFactor', 'baseColorMap', 'colorPaletteMap', 'instanceDiffuse', 'paletteBaseColor', 'useAnisotropic' }

local saved = {}        -- 'material@layer' -> { slot, fields = { key = old } }
local vehId

local function field(mat, k, layer) local v = mat:getField(k, layer) return v == nil and '' or tostring(v) end
local function truthy(v) return v == true or v == 1 or v == '1' or v == 'true' end

-- the paint layers of the player's car: those that take the car's colour (as carSurfaceFx_scratch decides)
local function paintLayers(veh)
  local out = {}
  for _, nm in ipairs(veh:getMaterialNames() or {}) do
    local mat = scenetree.findObject(nm)
    if mat and tostring(mat:getClassName()):lower() == 'material' and not truthy(mat:getField('translucent', 0)) then
      for layer = 0, (tonumber(mat:getField('activeLayers', 0)) or tonumber(mat.activeLayers) or 1) - 1 do
        local inst = truthy(mat:getField('instanceDiffuse', layer))
        local pal = field(mat, 'colorPaletteMap', layer)
        if inst or (pal ~= '' and truthy(mat:getField('paletteBaseColor', layer))) then out[#out + 1] = { name = nm, mat = mat, layer = layer } end
      end
    end
  end
  return out
end

local function player()
  local v = getPlayerVehicle and getPlayerVehicle(0)
  return v
end

function M.info()
  local veh = player()
  if not veh then return 'no player vehicle' end
  local out = {}
  for _, l in ipairs(paintLayers(veh)) do
    local parts = {}
    for _, k in ipairs(KEYS) do parts[#parts + 1] = k .. '=' .. (field(l.mat, k, l.layer):match('[^/]*$') or '') end
    out[#out + 1] = string.format('%s L%d: %s', l.name, l.layer, table.concat(parts, ' '))
  end
  if #out == 0 then return 'no paint layers found on this car' end
  return table.concat(out, '\n')
end

function M.run(slot)
  slot = slot or 'roughnessMap'
  local veh = player()
  if not veh then return 'no player vehicle' end
  M.restore()
  vehId = veh:getID()
  local layers = paintLayers(veh)
  if #layers == 0 then return 'no paint layers found on this car' end
  veh:createUITexture(TAG, PAGE .. '?m=grid&v=' .. PAGE_V, 1024, 1024, UI_TEXTURE_USAGE_AUTOMATIC, 5)
  for _, l in ipairs(layers) do
    local key = l.name .. '@' .. l.layer
    local s = { slot = slot, mat = l.mat, layer = l.layer, fields = {} }
    for _, k in ipairs({ slot, 'roughnessFactor', 'metallicFactor', 'clearCoatFactor' }) do s.fields[k] = field(l.mat, k, l.layer) end
    saved[key] = s
    l.mat:setField(slot, l.layer, TAG)
    l.mat:reload()
  end
  return string.format('canvas bound to %s on %d paint layer(s); look at the car: black discs, a band and a gradient bar should show as gloss (or metal) if the slot works', slot, #layers)
end

function M.noCoat()
  if next(saved) == nil then return 'run() first' end
  local n = 0
  for _, s in pairs(saved) do
    local cur = field(s.mat, 'clearCoatFactor', s.layer)
    if cur ~= '' then
      s.coatWas = cur
      s.mat:setField('clearCoatFactor', s.layer, '0')
      s.mat:reload()
      n = n + 1
    end
  end
  return n > 0 and (n .. ' layer(s) without clear coat') or 'these layers have no clearCoatFactor field'
end

function M.restore()
  local n = 0
  for _, s in pairs(saved) do
    s.mat:setField(s.slot, s.layer, s.fields[s.slot])
    if s.coatWas then s.mat:setField('clearCoatFactor', s.layer, s.coatWas) end
    s.mat:reload()
    n = n + 1
  end
  saved = {}
  local veh = vehId and getObjectByID and getObjectByID(vehId) or player()
  if veh and veh.destroyUITexture then pcall(function() veh:destroyUITexture(TAG) end) end
  vehId = nil
  return n .. ' layer(s) put back'
end

function M.onExtensionUnloaded() pcall(M.restore) end

return M
