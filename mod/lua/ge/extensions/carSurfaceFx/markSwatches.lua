-- Car Surface FX: a test map of the mark materials, not part of the mod (nothing loads it): one strip or stain of every type, dry and wet side by side, on the ground ahead
-- of the player's car, with a label each. For comparing in sun, shade, dusk, night and rain.
--   extensions.load('carSurfaceFx_markSwatches')
--   carSurfaceFx_markSwatches.run()       -- three blocks of rows ahead of the car: left of each pair is dry, right is wet
--   carSurfaceFx_markSwatches.run('rut')  -- only the types whose name has that in it
--   carSurfaceFx_markSwatches.clear()
-- test_bump (domes on the left, pits on the right) shows which way the normal maps are read: lit from the side the sun is on, a dome is bright on that side; if it looks
-- the other way round (pits where domes should be), rebuild the textures with tools/make_mark_textures.py --flip-green.
local M = {}

local materials = require('carSurfaceFx/markMaterials')
local roads, labels = {}, {}

local function frame()
  local v = getPlayerVehicle and getPlayerVehicle(0)
  if not v then return nil end
  local p, f = v:getPosition(), v:getDirectionVector()
  f = vec3(f.x, f.y, 0):normalized()
  return vec3(p.x, p.y, p.z), f, vec3(f.y, -f.x, 0)
end

local function road(material, a, b, width, length)
  local r = createObject('DecalRoad')
  r:setField('improvedSpline', 0, 'true')
  r:setField('material', 0, material)
  r:setField('overObjects', 0, 'true')
  r:setField('renderPriority', 0, 10)
  r:setField('textureLength', 0, tostring(length))
  r:registerObject('')
  if scenetree and scenetree.MissionGroup then scenetree.MissionGroup:add(r) end
  r:insertNode(a, width, 0)
  r:insertNode(b, width, 1)
  roads[#roads + 1] = r:getID()
end

function M.run(filter)
  M.clear()
  local p, f, r = frame()
  if not p then return 'no player vehicle' end
  local list = {}
  for _, t in ipairs(materials.index()) do
    if not filter or filter == '' or t.type:find(filter, 1, true) then list[#list + 1] = t end
  end
  if #list == 0 then return 'no mark types' .. (filter and (' with ' .. filter) or '') .. ' (is ' .. materials.INDEX .. ' there?)' end
  local missing = {}
  local perBlock = 7
  for i, t in ipairs(list) do
    local block, row = math.floor((i - 1) / perBlock), (i - 1) % perBlock
    local length = t.blob and 1.4 or 4
    local width = t.blob and 1.4 or math.max(0.5, t.width)
    local along = 8 + row * 5.5
    local across = (block - 1) * 7
    for col, name in ipairs({ t.dry, t.wet }) do
      local ok, why = materials.ensure(name)
      if not ok then missing[#missing + 1] = name .. ': ' .. tostring(why) else
        local centre = p + f * (along + length * 0.5) + r * (across + (col - 1.5) * 2.0)
        road(name, centre - f * (length * 0.5), centre + f * (length * 0.5), width, t.textureLength)
      end
    end
    labels[#labels + 1] = { pos = p + f * (along + length * 0.5) + r * (across - 2.6), text = t.type }
  end
  local msg = string.format('%d types (dry left, wet right), blocks of %d rows ahead of the car', #list, perBlock)
  if #missing > 0 then msg = msg .. '; materials that could not be made: ' .. table.concat(missing, ' | ') end
  return msg
end

function M.clear()
  for _, id in ipairs(roads) do
    local o = scenetree and scenetree.findObjectById(id)
    if o then o:deleteObject() end
  end
  roads, labels = {}, {}
  return 'cleared'
end

local white, black
function M.onPreRender()
  if #labels == 0 or not debugDrawer then return end
  white = white or ColorF(1, 1, 1, 1)
  black = black or ColorI(0, 0, 0, 180)
  for _, l in ipairs(labels) do debugDrawer:drawTextAdvanced(l.pos, String(l.text), white, true, false, black) end
end

function M.onExtensionUnloaded() M.clear() end

require('carSurfaceFx/guard').wrap(M, 'carSurfaceFx_markSwatches', { 'onPreRender' })

return M
