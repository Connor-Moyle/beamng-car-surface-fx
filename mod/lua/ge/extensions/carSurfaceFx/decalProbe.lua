-- Car Surface FX: is a ground decal lit? A test, not part of the mod (nothing loads it): two rows of plain white strips side by side on the ground ahead of the player's car,
-- one drawn by the dynamic decal manager (what the old skid marks used), one as DecalRoad objects with the game's own plain white material (a normal lit material). Same
-- ground, same sun, same shade: if the first row stays as bright as it is in the sun when the second goes dark in shade or at night, the decal manager does not light its
-- decals. Also lays a DecalRoad with any material by name (the game's own dirt tyre tracks, for one).
--   extensions.load('carSurfaceFx_decalProbe')
--   carSurfaceFx_decalProbe.run()                 -- both rows, 4 strips each, 5 m apart, 8 m ahead of the car (left: decal manager, right: lit decal road)
--   carSurfaceFx_decalProbe.road('m_dirt_tiretracks')   -- a 14 m strip of that material ahead of the car, on the ground
--   carSurfaceFx_decalProbe.info('m_dirt_tiretracks')   -- is that material loaded, with its stage fields
--   carSurfaceFx_decalProbe.clear()
local M = {}

local WHITE = 'art/surfacefx/probe_white.png'
local rows = {}          -- decal manager entries, added again every frame (it draws immediately)
local roads = {}         -- DecalRoad object ids made here

local function frame()
  local v = getPlayerVehicle and getPlayerVehicle(0)
  if not v then return nil end
  local p, f = v:getPosition(), v:getDirectionVector()
  f = vec3(f.x, f.y, 0):normalized()
  return vec3(p.x, p.y, p.z), f, vec3(f.y, -f.x, 0)       -- position, forward, right
end

local function road(material, from, to, width)
  local r = createObject('DecalRoad')
  r:setField('improvedSpline', 0, 'true')
  r:setField('material', 0, material)
  r:setField('overObjects', 0, 'true')
  r:setField('renderPriority', 0, 10)
  r:setField('textureLength', 0, tostring(math.max(1, (to - from):length())))
  r:registerObject('')
  if scenetree and scenetree.MissionGroup then scenetree.MissionGroup:add(r) end
  r:insertNode(from, width, 0)
  r:insertNode(to, width, 1)
  roads[#roads + 1] = r:getID()
  return r
end

function M.run()
  M.clear()
  local p, f, r = frame()
  if not p then return 'no player vehicle' end
  local start = p + f * 8
  for i = 0, 3 do
    local a = start + f * (i * 5) - r * 3                                  -- left: the decal manager
    rows[#rows + 1] = { texture = WHITE, position = vec3(a.x, a.y, a.z), forwardVec = vec3(f.x, f.y, 0), color = ColorF(1, 1, 1, 1), scale = vec3(2, 4, 3), fadeStart = 150, fadeEnd = 160 }
    local b = start + f * (i * 5) + r * 3                                  -- right: a DecalRoad
    road('BlankWhite', b - f * 2, b + f * 2, 2)
  end
  return string.format('%d decal manager strips (left) and %d decal roads (right); compare them in sun, shade, dusk, night, rain', #rows, #roads)
end

function M.road(material)
  local p, f = frame()
  if not p then return 'no player vehicle' end
  if not (scenetree and scenetree.findObject(material)) then return 'material ' .. tostring(material) .. ' is not loaded' end
  road(material, p + f * 6, p + f * 20, 2.2)
  return 'a 14 m strip of ' .. material .. ' ahead of the car'
end

function M.info(material)
  local m = scenetree and scenetree.findObject(material)
  if not m then return 'material ' .. tostring(material) .. ' is not loaded' end
  local out = {}
  for _, k in ipairs({ 'baseColorMap', 'normalMap', 'roughnessMap', 'ambientOcclusionMap', 'opacityMap', 'detailNormalMap', 'baseColorFactor', 'roughnessFactor', 'metallicFactor', 'opacityFactor' }) do
    out[#out + 1] = k .. '=' .. tostring(m:getField(k, 0))
  end
  out[#out + 1] = 'translucent=' .. tostring(m:getField('translucent', 0)) .. ' translucentZWrite=' .. tostring(m:getField('translucentZWrite', 0))
  return table.concat(out, '\n')
end

function M.clear()
  rows = {}
  for _, id in ipairs(roads) do
    local o = scenetree and scenetree.findObjectById(id)
    if o then o:deleteObject() end
  end
  roads = {}
  return 'cleared'
end

function M.onPreRender()
  if #rows > 0 and Engine and Engine.Render and Engine.Render.DynamicDecalMgr then Engine.Render.DynamicDecalMgr.addDecals(rows, #rows) end
end

function M.onExtensionUnloaded() M.clear() end

require('carSurfaceFx/guard').wrap(M, 'carSurfaceFx_decalProbe', { 'onPreRender' })

return M
