-- Car Surface FX rules: pure functions (no game calls), tested outside the game by tools/luatest.js.
local M = {}

M.RUNGS = 3                                            -- wet ladder: clone materials w1..w3
local FRACTION = { 0.33, 0.66, 1 }                     -- how wet each rung looks
local UP = { 0.08, 0.40, 0.75 }                        -- wetness needed to climb to rung 1, 2, 3
local HYST = 0.04                                      -- ...and how far it must fall below that to step back down
M.DROPLETS = '/art/surfacefx/droplets.normal.png'

local function clamp(x, a, b) return x < a and a or (x > b and b or x) end
M.clamp = clamp

-- the rung (0 = dry) for a wetness, with hysteresis so it does not flicker at a threshold
function M.level(w, cur)
  cur = cur or 0
  local l = cur
  while l < M.RUNGS and w >= UP[l + 1] do l = l + 1 end
  while l > 0 and w < UP[l] - HYST do l = l - 1 end
  return l
end

-- wetness 0..1 from what the sky is doing: Street Legal's value if it has one, else the rain object's drop count
function M.target(slWet, drops)
  if slWet then return clamp(slWet, 0, 1) end
  return clamp((drops or 0) / 800, 0, 1)
end

-- soaks in over ~25 s, dries over ~5 min
function M.wetStep(w, target, dt)
  if target > w then return math.min(target, w + dt / 25) end
  return math.max(target, w - dt / 300)
end

-- a material stage (one entry of Stages in a materials.json) is paint when it takes the car's colour or has a clear coat
function M.isPaintStage(st)
  if type(st) ~= 'table' then return false end
  if st.colorPaletteMap and st.colorPaletteMap ~= '' then return true end
  return (tonumber(st.clearCoatFactor) or 0) > 0
end

function M.isPaintMaterial(def)
  if type(def) ~= 'table' or type(def.Stages) ~= 'table' then return false end
  if def.translucent or def.alphaBlend then return false end
  for _, st in pairs(def.Stages) do if M.isPaintStage(st) then return true end end
  return false
end

local function color4(v)
  if type(v) == 'table' then return { v[1] or 1, v[2] or 1, v[3] or 1, v[4] or 1 } end
  return { 1, 1, 1, 1 }
end

-- the fields (name -> string for setField) one stage gets at a rung: darker, glossier, with beads of water
function M.wetFields(st, rung)
  local f = FRACTION[rung]
  local out = {}
  local c = color4(st.baseColorFactor)
  local k = 1 - 0.25 * f
  out.baseColorFactor = string.format('%.4f %.4f %.4f %.4f', c[1] * k, c[2] * k, c[3] * k, c[4])
  out.roughnessFactor = string.format('%.4f', (tonumber(st.roughnessFactor) or 1) * (1 - 0.5 * f))
  out.clearCoatRoughnessFactor = string.format('%.4f', (tonumber(st.clearCoatRoughnessFactor) or 1) * (1 - 0.5 * f))
  if not st.normalDetailMap or st.normalDetailMap == '' then
    out.normalDetailMap = M.DROPLETS
    out.normalDetailMapStrength = string.format('%.3f', 0.6 * f)
    if not st.detailScale then out.detailScale = '6 6' end
  end
  return out
end

-- a JSON value as the string setField takes
function M.fieldString(v)
  local t = type(v)
  if t == 'boolean' then return v and '1' or '0' end
  if t == 'table' then
    local p = {}
    for i, x in ipairs(v) do p[i] = M.fieldString(x) end
    return table.concat(p, ' ')
  end
  return tostring(v)
end

return M
