-- Car Surface FX rules: pure functions (no game calls), tested outside the game by tools/luatest.js.
local M = {}

M.RUNGS = 5                                            -- wet rungs: each has its own bead map (small sparse -> many, bigger, merged)
local FRACTION = { 0.2, 0.4, 0.6, 0.8, 1 }             -- how wet each rung looks
local UP = { 0.05, 0.20, 0.40, 0.60, 0.80 }            -- wetness needed to climb to rung 1..5
local HYST = 0.04                                      -- ...and how far it must fall below that to step back down
M.DROPLETS = '/art/surfacefx/droplets%d.normal.png'   -- one per rung
M.GLASS_MAP = '/art/surfacefx/glass.normal.png'
M.glassScale = '3 3'

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

-- The v1.5 fields copied from the live Material object, per stage (0..3) and for the whole material. Read with getField, so the clone matches
-- what the game actually loaded (every texture map and factor), whichever file defined it.
M.STAGE_FIELDS = { 'ambientOcclusionMap', 'ambientOcclusionMapUseUV', 'animFlags', 'baseColorFactor', 'baseColorMap', 'clearCoatBottomNormalMapStrength',
  'clearCoatFactor', 'clearCoatMap', 'clearCoatMapUseUV', 'clearCoatRoughnessFactor', 'colorPaletteMap', 'colorPaletteMapUseUV', 'detailBaseColorMapStrength',
  'detailMap', 'detailMapUseUV', 'detailMetallicMapStrength', 'detailNormalMap', 'detailNormalMapStrength', 'detailRoughnessMapStrength', 'detailScale',
  'emissiveFactor', 'emissiveIntensityNits', 'emissiveMap', 'emissiveMapUseUV', 'glow', 'metallicDetailMap', 'metallicFactor', 'metallicMap', 'metallicMapUseUV',
  'normalDetailMapUseUV', 'normalMap', 'normalMapStrength', 'normalMapUseUV', 'opacityDetailMap', 'opacityDetailMapUseUV', 'opacityFactor', 'opacityMap',
  'opacityMapUseUV', 'overlayMap', 'paletteBaseColor', 'paletteClearCoat', 'paletteClearCoatRoughness', 'paletteMetallic', 'paletteRoughness',
  'retroreflectiveColor', 'retroreflectivity', 'roughnessDetailMap', 'roughnessFactor', 'roughnessMap', 'roughnessMapUseUV', 'scrollDir', 'useAnisotropic',
  'vertColor', 'vertColorEmissive' }
M.TOP_FIELDS = { 'version', 'translucent', 'translucentBlendOp', 'translucentRecvShadows', 'translucentZWrite', 'doubleSided', 'alphaTest', 'alphaRef',
  'castShadows', 'invertBackFaceNormals', 'dynamicCubemap', 'cubemap', 'annotation', 'activeLayers', 'beamngDiffuseColorSlot', 'materialTag0', 'materialTag1',
  'materialTag2', 'materialTag3', 'detailMapScale0' }
M.STAGES = 4
local DETAIL_MAPS = { 'detailMap', 'roughnessDetailMap', 'metallicDetailMap', 'opacityDetailMap' }   -- other detail maps share detailScale: leave those stages alone
M.beadScale, M.beadStrength = '6 6', 0.4               -- tunable (carSurfaceFx.tune): how big and how strong the water beads are

local function set(v) return v ~= nil and v ~= '' end

-- stage = { field = string } read from the Material. A stage is paint when it takes the car's colour.
function M.isPaintStage(st) return type(st) == 'table' and set(st.colorPaletteMap) end

local function anyStage(stages, f)
  for _, st in pairs(stages) do if f(st) then return true end end
  return false
end

-- Which of a car's materials are body paint. mats = { { name, stages, meshes (count), version, translucent } }. Paint = a v1.5, opaque material with a palette
-- stage and a mesh count of at least 40% of the biggest such material (the body, not the wheels or the interior); if none has a palette, the biggest one.
function M.paintNames(mats)
  local cand, top = {}, 0
  for _, m in ipairs(mats) do
    if tonumber(m.version) == 1.5 and not (m.translucent == '1' or m.translucent == 'true') and m.meshes > 0 then
      cand[#cand + 1] = m
    end
  end
  local pal = {}
  for _, m in ipairs(cand) do
    if anyStage(m.stages, M.isPaintStage) then pal[#pal + 1] = m if m.meshes > top then top = m.meshes end end
  end
  local out = {}
  if #pal == 0 then
    local best
    for _, m in ipairs(cand) do if not best or m.meshes > best.meshes then best = m end end
    if best then out[best.name] = true end
    return out
  end
  for _, m in ipairs(pal) do if m.meshes >= 0.4 * top then out[m.name] = true end end
  return out
end

local function color4(v)
  local t = {}
  for x in tostring(v or ''):gmatch('%S+') do t[#t + 1] = tonumber(x) end
  return { t[1] or 1, t[2] or 1, t[3] or 1, t[4] or 1 }
end

-- the fields (name -> string for setField) one paint stage gets at a rung: darker, glossier, with beads of water (they replace the paint's own
-- orange-peel normal detail while wet: a water film hides it)
function M.wetFields(st, rung)
  local f = FRACTION[rung]
  local out = {}
  local c = color4(st.baseColorFactor)
  local k = 1 - 0.25 * f
  out.baseColorFactor = string.format('%.4f %.4f %.4f %.4f', c[1] * k, c[2] * k, c[3] * k, c[4])
  out.roughnessFactor = string.format('%.4f', (tonumber(st.roughnessFactor) or 1) * (1 - 0.5 * f))
  out.clearCoatRoughnessFactor = string.format('%.4f', (tonumber(st.clearCoatRoughnessFactor) or 1) * (1 - 0.5 * f))
  local own = false
  for _, d in ipairs(DETAIL_MAPS) do if set(st[d]) then own = true end end
  if not own then
    out.detailNormalMap = string.format(M.DROPLETS, rung)
    out.detailNormalMapStrength = string.format('%.3f', M.beadStrength * f)
    out.detailScale = M.beadScale
  end
  return out
end

-- A paint ({ baseColor = {r,g,b,a}, metallic, roughness, clearcoat, clearcoatRoughness }) with dirt d (0..1) on it. Low dirt is a light tan dust and
-- barely changes the paint (k = d^1.5); high dirt is dark mud that takes the gloss and the metal off.
local DUST, MUD = { 0.55, 0.47, 0.36 }, { 0.30, 0.22, 0.14 }
function M.dirtPaint(p, d)
  local k = d * math.sqrt(d)
  local km = 0.85 * k                                    -- colour never fully replaced: some of the paint shows through
  local c = p.baseColor
  local tint = {}
  for i = 1, 3 do tint[i] = DUST[i] + (MUD[i] - DUST[i]) * d end
  local function mix(a, b) return a + (b - a) * k end
  local function mixc(a, b) return a + (b - a) * km end
  return { baseColor = { mixc(c[1], tint[1]), mixc(c[2], tint[2]), mixc(c[3], tint[3]), c[4] or 1 }, metallic = (p.metallic or 0) * (1 - 0.8 * k),
    roughness = mix(p.roughness or 0.5, 0.95), clearcoat = (p.clearcoat or 0) * (1 - k), clearcoatRoughness = mix(p.clearcoatRoughness or 0, 0.9) }
end

-- How much dirt a ground model puts on the car, by its name (core_environment.groundModels keys: MUD, DIRT, GRAVEL...).
local GROUND = { { 'mud', 1 }, { 'clay', 0.7 }, { 'dirt', 0.6 }, { 'sand', 0.5 }, { 'gravel', 0.5 }, { 'grass', 0.25 }, { 'snow', 0.15 }, { 'rock', 0.15 } }
function M.groundWeight(name)
  local n = tostring(name):lower()
  for _, g in ipairs(GROUND) do if n:find(g[1], 1, true) then return g[2] end end
  return 0
end

-- dirt after dt seconds on ground of weight w at speed (m/s): full mud at speed takes ~90 s, wet ground builds faster
function M.dirtStep(d, dt, w, speed, wet)
  local rate = w * (0.4 + 0.6 * clamp((speed or 0) / 20, 0, 1)) * (1 + (wet or 0)) / 90
  return clamp(d + rate * dt, 0, 1)
end

-- rain washes the car: ~7 min of full rain from dirty to clean
function M.washStep(d, dt, wet) return clamp(d - (wet or 0) * dt / 420, 0, 1) end

-- Glass (windscreen, side windows): the same water beads on the glass material itself, no colour change; any detail map the glass already has stays.
function M.isGlassName(name)
  local n = tostring(name):lower()
  return n:find('glass', 1, true) ~= nil and not n:find('dmg', 1, true) and not n:find('broken', 1, true)
end

-- sx, sy: the scroll of the glass's UVs in detail tiles per second (the streak axis is sy; see M.glassScroll)
function M.glassFields(st, rung, sx, sy)
  for _, d in ipairs(DETAIL_MAPS) do if set(st[d]) then return {} end end
  return { detailNormalMap = M.GLASS_MAP, detailNormalMapStrength = string.format('%.3f', M.beadStrength * FRACTION[rung]), detailScale = M.glassScale,
    animFlags = '1', scrollDir = string.format('%.2f %.2f', sx or 0, sy or 0) }
end

-- Where the water on the glass goes: speed (m/s) pushes it back up the glass, braking (aLong < 0, m/s^2) throws it forward and down, accelerating pushes it back,
-- cornering (aLat, + to the right) slides it sideways; a stopped car lets it run down slowly. Returns sx, sy rounded to 0.05 so small changes cost no reload.
-- M.glassAxis = { x = 0, y = 1 }: which UV axis is "down the glass" (differs per car; carSurfaceFx.tuneGlass); y > 0 scrolls the map toward +y.
M.glassAxis = { x = 0, y = 1 }
function M.glassScroll(speed, aLong, aLat)
  local down = 0.04 - (speed / 30) * (speed / 30) * 0.3 - aLong * 0.012
  local side = (aLat or 0) * 0.012
  down, side = clamp(down, -0.3, 0.3), clamp(side, -0.2, 0.2)
  local function q(v) return math.floor(v / 0.05 + 0.5) * 0.05 end
  local a = M.glassAxis
  return q(a.x * down - a.y * side), q(a.y * down + a.x * side)
end

return M
