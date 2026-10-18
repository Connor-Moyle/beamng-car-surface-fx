-- Car Surface FX rules: pure functions (no game calls), tested outside the game by tools/luatest.js.
local M = {}

M.RUNGS = 5                                            -- wet rungs: each has its own bead map (small sparse -> many, bigger, merged)
local FRACTION = { 0.2, 0.4, 0.6, 0.8, 1 }             -- how wet each rung looks
local UP = { 0.05, 0.20, 0.40, 0.60, 0.80 }            -- wetness needed to climb to rung 1..5
local HYST = 0.04                                      -- ...and how far it must fall below that to step back down
M.DROPLETS = '/art/surfacefx/droplets%d.normal.png'   -- one per rung

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
M.beadScale, M.beadStrength = '12 12', 0.35               -- tunable (carSurfaceFx.tune): how big and how strong the water beads are

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

-- ---------------------------------------------------------------------------------------------------------------------
-- Dirt: four kinds, each with its own tint, how strongly it shows, and how fast it builds and washes off. Amounts are 0..1 per kind.
-- ---------------------------------------------------------------------------------------------------------------------
M.KINDS = { 'dust', 'mud', 'rubber', 'grime', 'snow', 'bugs' }
local TINT = { dust = { 0.62, 0.53, 0.40 }, mud = { 0.30, 0.22, 0.14 }, rubber = { 0.05, 0.05, 0.05 }, grime = { 0.30, 0.29, 0.27 }, snow = { 0.93, 0.95, 0.98 }, bugs = { 0.14, 0.11, 0.07 } }
local SHOW = { dust = 0.55, mud = 0.85, rubber = 0.45, grime = 0.5, snow = 0.95, bugs = 0.35 }              -- how much of the paint a full amount of that kind covers
local GLOSS = { dust = 0.7, mud = 1, rubber = 0.5, grime = 0.6, snow = 0.5, bugs = 0.1 }                  -- how much of the gloss and metal it takes off
M.CAP = { dust = 1, mud = 1, rubber = 1, grime = 0.6, snow = 1, bugs = 0.5 }                             -- a road film never gets as thick as mud

function M.dirtNew() return { dust = 0, mud = 0, rubber = 0, grime = 0, snow = 0, bugs = 0 } end

-- A paint ({ baseColor = {r,g,b,a}, metallic, roughness, clearcoat, clearcoatRoughness }) with these dirt amounts on it: the colour is the kinds' tints weighted by
-- how much each shows (k = amount^1.5 x SHOW), low amounts barely touch the paint, and gloss and metal go with the amounts.
function M.dirtPaint(p, d)
  local cover, gloss, tint, wsum = 1, 1, { 0, 0, 0 }, 0
  for _, kind in ipairs(M.KINDS) do
    local a = d[kind] or 0
    local k = a * math.sqrt(a) * SHOW[kind]
    cover = cover * (1 - k)
    gloss = gloss * (1 - (k / SHOW[kind]) * GLOSS[kind])
    for i = 1, 3 do tint[i] = tint[i] + TINT[kind][i] * k end
    wsum = wsum + k
  end
  local T = 1 - cover
  local c = p.baseColor
  local out = { baseColor = { c[1], c[2], c[3], c[4] or 1 }, metallic = (p.metallic or 0) * gloss, roughness = p.roughness or 0.5, clearcoat = (p.clearcoat or 0) * gloss,
    clearcoatRoughness = p.clearcoatRoughness or 0 }
  if wsum > 0 then
    for i = 1, 3 do out.baseColor[i] = c[i] + (tint[i] / wsum - c[i]) * T * 0.9 end
    out.roughness = out.roughness + (0.95 - out.roughness) * T
    out.clearcoatRoughness = out.clearcoatRoughness + (0.9 - out.clearcoatRoughness) * T
  end
  return out
end

-- What a ground model puts on the car, by name (core_environment.groundModels keys). Returns class, weight: 'mud' / 'loose' (dust when dry, mud when wet) / 'road' / nil.
local LOOSE = { { 'clay', 0.7 }, { 'dirt', 0.6 }, { 'sand', 0.5 }, { 'gravel', 0.5 }, { 'grass', 0.25 }, { 'snow', 0.15 }, { 'rock', 0.15 } }
local ROAD = { 'asphalt', 'concrete', 'tarmac', 'road', 'cobble', 'paved', 'brick' }
function M.groundClass(name)
  local n = tostring(name):lower()
  if n:find('mud', 1, true) then return 'mud', 1 end
  for _, g in ipairs(LOOSE) do if n:find(g[1], 1, true) then return 'loose', g[2] end end
  for _, r in ipairs(ROAD) do if n:find(r, 1, true) then return 'road', 1 end end
  return nil, 0
end

-- One report from the car, covering dt seconds: fractions of that time on loose ground (weighted), mud, road, skidding, and with a wheel in water; speed in m/s.
-- Dry loose ground gives dust, wet gives mud; mud ground and wet loose ground give mud; tarmac gives a slow film, faster in the wet; skids lay rubber.
function M.dirtBuild(d, dt, r, speed, wet)
  local sf = 0.4 + 0.6 * clamp((speed or 0) / 20, 0, 1)
  local wetK = clamp((wet or 0) * 1.5, 0, 1)
  local out = {}
  out.dust = d.dust + (r.loose or 0) * (1 - wetK) * sf * dt / 60
  out.mud = d.mud + ((r.mud or 0) + (r.loose or 0) * wetK) * sf * (1 + (wet or 0) * 0.5) * dt / 90
  out.rubber = d.rubber + (r.slip or 0) * dt / 25
  out.grime = d.grime + (r.road or 0) * sf * (1 + (wet or 0)) * dt / 1200
  -- snow settles while it snows (a car that stands takes all of it, a moving one little) and is blown off above SNOW_BLOW m/s; above warm it melts
  local snowing, v = r.snowing or 0, speed or 0
  out.snow = (d.snow or 0) + snowing * (v < M.SNOW_BLOW and 1 or 0.15) * dt / 90 - (v > M.SNOW_BLOW and (v - M.SNOW_BLOW) * dt / 40 or 0) - (r.warm and dt / 900 or 0)
  -- bugs hit the nose in fast driving (not in the wet), a few per minute
  out.bugs = (d.bugs or 0) + ((wet or 0) < 0.3 and v > M.BUG_SPEED and (v - M.BUG_SPEED) / 20 * dt / 300 or 0)
  for _, k in ipairs(M.KINDS) do out[k] = clamp(out[k], 0, M.CAP[k]) end
  return out
end

M.SNOW_BLOW, M.BUG_SPEED = 8, 18

-- Frost on glass, 0..1 per car. Builds in the cold (air below FROST_AIR C) while the engine is cold and it is not raining, faster the colder it is; clears with the
-- engine's warm-up (coolant above FROST_ENGINE C), by rain and by the wipers (the caller handles the arc). Returns the new frost and, for the rising clear-up edge, nothing else.
M.FROST_AIR, M.FROST_ENGINE = 2, 30
function M.frostStep(f, dt, airC, engineC, wet)
  if airC == nil then return f end
  if airC < M.FROST_AIR and (engineC or airC) < M.FROST_ENGINE and (wet or 0) < 0.2 then
    f = f + dt / 240 * clamp((M.FROST_AIR - airC) / 6, 0.2, 1.5)
  end
  if engineC and engineC > M.FROST_ENGINE then f = f - dt * clamp((engineC - M.FROST_ENGINE) / 60, 0.02, 0.5) end
  if airC > M.FROST_AIR + 1 then f = f - dt / 120 end
  f = f - (wet or 0) * dt / 90
  return clamp(f, 0, 1)
end

-- Road spray from a car ahead (0..1): c = { dist (m, along your direction), lateral (m, sideways offset), align (the two cars' heading dot, 1 = same way), speed (its m/s),
-- len (its length in m) }. Within SPRAY_RANGE ahead, roughly in your lane, going the same way and fast enough; stronger the faster and the closer, and for long vehicles.
M.SPRAY_RANGE = 25
function M.spray(c)
  if not (c.dist > 1 and c.dist < M.SPRAY_RANGE and math.abs(c.lateral) < 2.4 and c.align > 0.6 and c.speed > 7) then return 0 end
  local sizeK = clamp(0.7 + ((c.len or 4.5) - 4) / 10, 0.7, 1.6)
  return clamp(clamp((c.speed - 7) / 20, 0, 1) * (1 - c.dist / M.SPRAY_RANGE) ^ 1.2 * sizeK, 0, 1)
end
-- how much of that spray there is on a road this wet (wet 0..1)
function M.sprayWet(wet) return clamp(((wet or 0) - 0.2) / 0.6, 0, 1) end

-- A puddle splash on your own car: the shares (0..1) of the last interval a left / right wheel was in water, the speed (m/s) and a depth 0..1 (1 = deep). Above SPLASH_SPEED
-- the wheels throw dirty water up the lower body on their side: expected splats per side, and the sheet of water over the windscreen (0..1) that a deep puddle at speed throws.
M.SPLASH_SPEED = 10
function M.splash(speed, shareL, shareR, depth)
  local over = math.max(0, (speed or 0) - M.SPLASH_SPEED)
  local d = clamp(depth or 0.5, 0, 1)
  local sheet = 0
  if (shareL or 0) + (shareR or 0) > 1.2 and (speed or 0) > 14 then sheet = clamp((speed - 14) / 12, 0, 1) * d end
  return (shareL or 0) * over / 3 * (0.5 + d), (shareR or 0) * over / 3 * (0.5 + d), sheet
end

-- snow weather: precipitation with the air below SNOW_AIR C (snowing 0..1), and whether it is warm enough to melt it
M.SNOW_AIR = 1.5
function M.snowing(drops, airC)
  if airC == nil or airC > M.SNOW_AIR then return 0 end
  return clamp((drops or 0) * 4, 0, 1)
end

-- washing: rain (wet 0..1, per second) and water (the share of the time a wheel was in water). Dust goes fast, mud and film slowly, rubber hardly at all.
local RAIN = { dust = 60, mud = 420, grime = 900, rubber = 6000, snow = 400, bugs = 500 }                -- seconds of full rain to wash a full amount off
local WATER = { dust = 3, mud = 12, grime = 40, rubber = 200, snow = 15, bugs = 30 }                   -- seconds in water
function M.dirtWash(d, dt, wet, water)
  local out = {}
  for _, k in ipairs(M.KINDS) do
    out[k] = clamp((d[k] or 0) - (wet or 0) * dt / RAIN[k] - (water or 0) * dt / WATER[k], 0, 1)
  end
  return out
end

-- a car wash takes off `amount` (0..1) of every kind
function M.dirtClean(d, amount)
  local out = {}
  for _, k in ipairs(M.KINDS) do out[k] = clamp((d[k] or 0) - (amount or 1), 0, 1) end
  return out
end

function M.dirtTotal(d)
  local t = 0
  for _, k in ipairs(M.KINDS) do t = t + (d[k] or 0) end
  return t
end

-- Glass (windscreen, side windows): the same water beads on the glass material itself, no colour change; any detail map the glass already has stays.
function M.isGlassName(name)
  local n = tostring(name):lower()
  return n:find('glass', 1, true) ~= nil and not n:find('dmg', 1, true) and not n:find('broken', 1, true) and not n:find('invisible', 1, true) and not n:find('crack', 1, true)
end

-- The glass takes its water from a per-car, per-material web canvas (vehicles/common/carSurfaceFx/glass.html) named '@csfx_<material>': the engine resolves a '@tag'
-- texture only in the colour-type slots (baseColorMap, emissiveMap...), while a normal map or detail map name gets the material's folder put in front of it and fails.
-- So the canvas REPLACES the glass's own base colour map: the page draws that image first (the original path is in its URL) and the drops on top.
function M.glassTag(name) return '@csfx_' .. tostring(name):gsub('[^%w_]', '_') end

-- The inside glass (name ends in 'int') is clear, so a colour change on it is invisible, and the engine does not resolve a '@tag' in its opacity map (tried): its EMISSIVE map
-- becomes the canvas instead (light adds to the picture whatever the glass opacity is; the page draws only the glints and bright rims).
M.insideMode = 'emissive'                                         -- or 'color' (carSurfaceFx.insideMode): which slot the inside glass's canvas goes in
M.outsideMode = 'color'                                           -- the outside glass: 'color' (the canvas replaces the tint map; the game's tint image cannot be read by the page, a flat dark tint stands in) or 'emissive' (glints and rims only, the glass keeps its own look)
function M.glassMode(name) return tostring(name):lower():find('int$') and M.insideMode or M.outsideMode end

-- the map the canvas replaces and the original image under the drops: field, path (nil when the canvas has no image under it, as with light only)
function M.glassMap(st, mode)
  if mode == 'emissive' then return 'emissiveMap', nil end
  if not set(st.baseColorMap) then return nil end                 -- no tint map to draw under the drops: leave this glass alone
  return 'baseColorMap', st.baseColorMap
end

M.glassEmissive = 0.4                                             -- how bright the inside drops glint (emissiveFactor)
function M.glassFields(st, tag, mode)
  local field = M.glassMap(st, mode or 'color')
  if not field then return {} end
  local out = { [field] = tag }
  if mode == 'emissive' then out.emissiveFactor = string.format('%.2f %.2f %.2f', M.glassEmissive, M.glassEmissive, M.glassEmissive) end
  return out
end

-- (x, y): the direction that is DOWN the glass in the glass material's UV space; differs per car, set with carSurfaceFx.tuneGlass
M.glassAxis = { x = 0, y = 1 }
M.glassTint, M.glassPasses = 0.5, 1                             -- colour glass: how dark the tint is drawn, how often the image is squared (see glass.js)
M.glassSize = 3.0                                          -- drop size and density on the window canvas (a window covers only part of the texture)

return M
