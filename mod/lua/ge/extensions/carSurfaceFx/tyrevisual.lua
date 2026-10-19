-- Car Surface FX: how worn a tyre looks (a first test, loaded by hand, nothing starts it). The car's own tyre materials keep their tread; at a wear amount above 0.3 a detail normal map is laid over
-- them (worn rubber, then the cord weave of the belts as the tread is gone, and a damage map over the top for a blown or gouged tyre), by editing the material's own stage fields the way the wet
-- paint does, and put back exactly by clear().
--   extensions.load('carSurfaceFx_tyrevisual')
--   carSurfaceFx_tyrevisual.list()          -- the tyre materials of the player's car
--   carSurfaceFx_tyrevisual.set(0.9)        -- 0 new .. 1 worn to the belts (what the wear rules will report); set(0.9, true) adds the damage map
--   carSurfaceFx_tyrevisual.clear()
local M = {}

local PATH = '/art/surfacefx/tyres/'
local WORN, BELTS, DAMAGE = PATH .. 'tyre_worn.normal.png', PATH .. 'tyre_belts.normal.png', PATH .. 'tyre_damage.normal.png'
local FIELDS = { 'detailNormalMap', 'detailNormalMapStrength', 'detailScale' }
local saved = {}                                   -- material name -> { field -> original }

local function field(mat, name) return tostring(mat:getField(name, 0) or '') end

local function tyreMaterials()
  local out = {}
  local veh = be and be:getPlayerVehicle(0)
  if not veh then return out end
  for _, name in ipairs(veh:getMaterialNames() or {}) do
    local n = name:lower()
    if (n:find('tire', 1, true) or n:find('tyre', 1, true)) and not n:find('shadow', 1, true) and not n:find('rim', 1, true) then out[#out + 1] = name end
  end
  return out
end

function M.list() return table.concat(tyreMaterials(), ', ') end

local function put(name, values)
  local mat = scenetree.findObject(name)
  if not mat then return false end
  if not saved[name] then
    saved[name] = {}
    for _, f in ipairs(FIELDS) do saved[name][f] = field(mat, f) end
  end
  for f, v in pairs(values) do mat:setField(f, 0, v) end
  mat:reload()
  return true
end

-- wear 0..1; damage true lays the damage map over the stage
function M.set(wear, damage)
  wear = math.max(0, math.min(1, tonumber(wear) or 0))
  if wear <= 0.3 and not damage then return M.clear() end
  local map = damage and DAMAGE or (wear >= 0.75 and BELTS or WORN)
  local strength = damage and 1 or math.min(1, (wear - 0.3) * 1.6)
  local n = 0
  for _, name in ipairs(tyreMaterials()) do
    if put(name, { detailNormalMap = map, detailNormalMapStrength = string.format('%.2f', strength), detailScale = '3 3' }) then n = n + 1 end
  end
  return string.format('wear %.2f on %d tyre materials (%s)', wear, n, map:match('[^/]+$'))
end

function M.clear()
  local n = 0
  for name, orig in pairs(saved) do
    local mat = scenetree.findObject(name)
    if mat then
      for f, v in pairs(orig) do mat:setField(f, 0, v) end
      mat:reload()
      n = n + 1
    end
  end
  saved = {}
  return 'restored ' .. n .. ' tyre materials'
end

function M.onExtensionUnloaded() pcall(M.clear) end

return M
