-- Car Surface FX: a test of the game's own grass flattening (the surface mask clipmap), not part of the mod (nothing loads it).
-- BeamNG 0.39 ships a surface mask that the ground cover (grass) shader reads: flatten, bend direction and cut per spot. The engine global `SurfaceMaskClipmap` takes circle
-- and line stamps; util_surfaceMaskWheels (shipped, off by default) stamps the player's wheels. This stamps by hand so the effect can be seen and measured.
--   extensions.load('carSurfaceFx_grassProbe')
--   carSurfaceFx_grassProbe.status()         -- is the mask there, is the game's own wheel stamper on, the clipmap's state at the car's page
--   carSurfaceFx_grassProbe.flatten()        -- a flattened circle (radius 2.5 m) 8 m ahead of the car, and a flattened line 14 m long beside it
--   carSurfaceFx_grassProbe.cut()            -- a circle with mark 1 (the grass is removed there) 8 m ahead, and a line beside it
--   carSurfaceFx_grassProbe.fan()            -- circles with the bend direction visible: flatten 1 at several spots in a row
--   carSurfaceFx_grassProbe.clear()          -- the whole mask empty again (the engine has no clearing of a region)
local M = {}

local function frame()
  local v = getPlayerVehicle and getPlayerVehicle(0)
  if not v then return nil end
  local p, f = v:getPosition(), v:getDirectionVector()
  f = vec3(f.x, f.y, 0):normalized()
  return vec3(p.x, p.y, p.z), f, vec3(f.y, -f.x, 0)
end

local function mask()
  local m = rawget(_G, 'SurfaceMaskClipmap')
  if not m then return nil, 'there is no SurfaceMaskClipmap in this game' end
  return m
end

local function ready(m, p)
  local ok, err = pcall(function()
    if getCurrentLevelIdentifier and getCurrentLevelIdentifier() then m:init('/temp/levels/' .. getCurrentLevelIdentifier() .. '/dynamicTiles') end
    m:setCenter(p.x, p.y)
  end)
  return ok, err
end

function M.status()
  local m, why = mask()
  if not m then return why end
  local p = frame()
  local out = { 'SurfaceMaskClipmap present' }
  out[#out + 1] = 'util_surfaceMaskWheels: ' .. (rawget(_G, 'util_surfaceMaskWheels') and ('loaded, enabled=' .. tostring(util_surfaceMaskWheels.enabled)) or 'not loaded')
  if p then
    local ok, s = pcall(function() return m:getDebugState(math.floor(p.x / 16), math.floor(p.y / 16)) end)
    if ok and type(s) == 'table' then
      for _, k in ipairs({ 'residentPages', 'originPageX', 'originPageY', 'pendingMasks', 'pendingLoads', 'dispatchSubmitMs', 'dispatchedTexels', 'savedPagesLast', 'loadedPagesLast', 'pendingSaves' }) do out[#out + 1] = k .. '=' .. tostring(s[k]) end
    else
      out[#out + 1] = 'getDebugState: ' .. tostring(s) .. ' (try M.debug(true) first)'
    end
  end
  return table.concat(out, '\n')
end

function M.debug(on)
  local m, why = mask()
  if not m then return why end
  m:setDebugEnabled(on and true or false)
  return 'clipmap debug ' .. tostring(on and true or false)
end

function M.flatten()
  local m, why = mask()
  if not m then return why end
  local p, f, r = frame()
  if not p then return 'no player vehicle' end
  local ok, err = ready(m, p)
  if not ok then return 'could not set up the mask: ' .. tostring(err) end
  local c = p + f * 8
  m:maskCircleWorld(c.x, c.y, 2.5, 1, 0)                                  -- x, y, radius, flatten, mark
  local a, b = p + f * 4 + r * 5, p + f * 18 + r * 5
  m:maskLineWorld(a.x, a.y, b.x, b.y, 1.6, 1, 0)                          -- x1, y1, x2, y2, width, flatten, mark
  return 'flattened: a circle 8 m ahead, a line 14 m long to the right'
end

function M.cut()
  local m, why = mask()
  if not m then return why end
  local p, f, r = frame()
  if not p then return 'no player vehicle' end
  local ok, err = ready(m, p)
  if not ok then return 'could not set up the mask: ' .. tostring(err) end
  local c = p + f * 8
  m:maskCircleWorld(c.x, c.y, 2.5, 1, 1)
  local a, b = p + f * 4 + r * 5, p + f * 18 + r * 5
  m:maskLineWorld(a.x, a.y, b.x, b.y, 1.6, 1, 1)
  return 'cut (mark 1): a circle 8 m ahead, a line 14 m long to the right'
end

function M.fan()
  local m, why = mask()
  if not m then return why end
  local p, f, r = frame()
  if not p then return 'no player vehicle' end
  local ok, err = ready(m, p)
  if not ok then return 'could not set up the mask: ' .. tostring(err) end
  for i = 0, 4 do
    local c = p + f * (6 + i * 3) - r * 4
    m:maskCircleWorld(c.x, c.y, 1.2, 0.3 + 0.175 * i, 0)                 -- more flatten each step
  end
  return 'five circles to the left with flatten 0.3 to 1.0'
end

function M.clear()
  local m, why = mask()
  if not m then return why end
  m:clear()
  return 'mask cleared'
end

return M
