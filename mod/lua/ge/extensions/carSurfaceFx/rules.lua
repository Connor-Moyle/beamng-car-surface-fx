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
  return math.max(target, w - dt / 100)
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
function M.isClearCoated(st) return type(st) == 'table' and (tonumber(st.clearCoatFactor) or 0) >= 0.3 end
function M.isPaintStage(st) return type(st) == 'table' and set(st.colorPaletteMap) end

local function anyStage(stages, f)
  for _, st in pairs(stages) do if f(st) then return true end end
  return false
end

-- Which of a car's materials are body paint. mats = { { name, stages, meshes (count), version, translucent } }. Paint = a v1.5, opaque material with a palette
-- stage and a mesh count of at least 40% of the biggest such material (the body, not the wheels or the interior); if none has a palette, the biggest one.
function M.paintNames(mats)
  local out = M.mainPaint(mats)
  for _, m in ipairs(mats) do                                         -- and the other clear-coated exterior panels: a carbon roof, a contrast roof, mirrors (often translucent or small materials)
    if not out[m.name] and tonumber(m.version) == 1.5 and (m.meshes or 0) > 0 and anyStage(m.stages, M.isClearCoated) and not M.isLampName(m.name) and not M.isEmissive(m.stages) then out[m.name] = true end
  end
  return out
end

-- The rest of the outside of the car (bumpers, trim, mirrors, wheels, grilles, seals): every opaque material that is not paint, not glass and not the inside, the engine or a screen.
local NOT_OUTSIDE = { 'interior', 'seat', 'gauge', 'screen', 'navi', 'stitch', 'engine', 'mechanical', 'dash', 'steer', 'carpet', 'headliner', 'debug', 'stripped', 'dmg', 'damage', 'broken', 'invisible', 'glow' }
function M.trimNames(mats, paint)
  local out = {}
  for _, m in ipairs(mats) do
    local n = tostring(m.name):lower()
    local bad = false
    for _, w in ipairs(NOT_OUTSIDE) do if n:find(w, 1, true) then bad = true break end end
    if not bad and not M.isLampName(n) and not M.isEmissive(m.stages) and not paint[m.name] and tonumber(m.version) == 1.5 and not (m.translucent == '1' or m.translucent == 'true') and (m.meshes or 0) > 0 and not M.isGlassName(m.name) then
      out[m.name] = true
    end
  end
  return out
end

function M.mainPaint(mats)
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
function M.wetFields(st, rung, trim)
  local f = FRACTION[rung]
  local out = {}
  local c = color4(st.baseColorFactor)
  local k = 1 - (trim and 0.35 or 0.25) * f                          -- black plastic: darker and much smoother when wet, or it looks the same dry
  out.baseColorFactor = string.format('%.4f %.4f %.4f %.4f', c[1] * k, c[2] * k, c[3] * k, c[4])
  out.roughnessFactor = string.format('%.4f', (tonumber(st.roughnessFactor) or 1) * (1 - (trim and 0.85 or 0.65) * f))
  out.clearCoatRoughnessFactor = string.format('%.4f', (tonumber(st.clearCoatRoughnessFactor) or 1) * (1 - 0.5 * f))
  local own = false
  for _, d in ipairs(DETAIL_MAPS) do if set(st[d]) then own = true end end
  if not own then
    out.detailNormalMap = string.format(M.DROPLETS, rung)
    out.detailNormalMapStrength = string.format('%.3f', M.beadStrength * f * (trim and 1.4 or 1))
    out.detailScale = M.beadScale
  end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Dirt: four kinds, each with its own tint, how strongly it shows, and how fast it builds and washes off. Amounts are 0..1 per kind.
-- ---------------------------------------------------------------------------------------------------------------------
M.KINDS = { 'dust', 'mud', 'rubber', 'grime', 'snow', 'bugs' }
local TINT = { dust = { 0.62, 0.53, 0.40 }, mud = { 0.30, 0.22, 0.14 }, rubber = { 0.05, 0.05, 0.05 }, grime = { 0.30, 0.29, 0.27 }, snow = { 0.93, 0.95, 0.98 }, bugs = { 0.14, 0.11, 0.07 } }
local SHOW = { dust = 0.35, mud = 0.5, rubber = 0.45, grime = 0.5, snow = 0.95, bugs = 0.35 }              -- how much of the paint a full amount of that kind covers
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
-- r.spin (optional): the fastest tyre surface speed in m/s. What is thrown follows the tyres, not the car: spinning in mud at 3 m/s throws as much as driving at the wheel speed.
function M.dirtBuild(d, dt, r, speed, wet)
  local sf = 1.85 * clamp((math.max(speed or 0, r.spin or 0) / 30) ^ 1.5, 0, 1.5)    -- spray grows with the throw speed (1 at 20 m/s, 2.8 at 45) and a standing car throws none
  local wetK = clamp((wet or 0) * 1.5, 0, 1)
  local out = {}
  out.dust = d.dust + ((r.loose or 0) * (1 - wetK) * math.max(sf, 0.1) * dt / 60) + ((r.road or 0) * (1 - wetK) * math.max(sf, 0.1) * dt / M.DUST_ROAD) - ((r.loose or 0) == 0 and math.max(0, (speed or 0) - 25) * dt / 1500 or 0)   -- dust settles slowly on a parked car; only highway wind off the dirt sheds it      -- loose ground: fast; dry tarmac: a thin film, slowly
  local mudSf = (speed or 0) > 2 and math.max(sf, 0.35) or sf                      -- wet ground sticks to a rolling tyre even slowly (a standing car still throws none)
  out.mud = d.mud + ((r.mud or 0) + (r.loose or 0) * wetK * 0.5) * mudSf * (1 + (wet or 0) * 0.5) * dt / 90 - (((speed or 0) > 12 and (wet or 0) < 0.1 and (r.mud or 0) + (r.loose or 0) == 0) and dt / 1800 or 0)   -- dry mud flakes off at speed, but never while it is being thrown on
  out.rubber = d.rubber + (r.slip or 0) * dt / 12
  out.grime = d.grime + (r.road or 0) * sf * dt * ((1 - wetK) / 1200 + wetK / 400)              -- wet tarmac throws a road film three times faster
  -- snow settles while it snows (a car that stands takes all of it, a moving one little) and is blown off above SNOW_BLOW m/s; above warm it melts
  local snowing, v = r.snowing or 0, speed or 0
  out.snow = (d.snow or 0) + snowing * (v < M.SNOW_BLOW and 1 or 0.15) * dt / 180 - (v > M.SNOW_BLOW and (v - M.SNOW_BLOW) * dt / 40 or 0) - (r.warm and dt / 900 or 0)
  -- bugs hit the nose in fast driving, by the air temperature and the time of day (r.airC, r.tod are optional)
  out.bugs = (d.bugs or 0) + M.bugRate(v, r.airC, r.tod, wet) * dt
  for _, k in ipairs(M.KINDS) do out[k] = clamp(out[k], 0, M.CAP[k]) end
  return out
end

M.SNOW_BLOW, M.BUG_SPEED, M.DUST_ROAD = 8, 18, 400

-- ---- bugs. Insects fly in warm air and at dusk and dawn, few below BUG_COLD C, none in rain; the nose collects them above BUG_SPEED m/s.
M.BUG_COLD, M.BUG_WARM = 12, 22
-- 0..1.4: how many insects are about. airC nil = unknown (treated as mild); tod = the game's time of day 0..1 (0 noon, 0.245 sunset, 0.775 sunrise), nil = day
function M.bugActivity(airC, tod, wet)
  if (wet or 0) >= 0.3 then return 0 end
  local a = airC == nil and 0.7 or clamp((airC - M.BUG_COLD) / (M.BUG_WARM - M.BUG_COLD), 0, 1)
  if airC and airC > 38 then a = a * 0.6 end                                -- too hot for them too
  local dusk = 0
  if tod then
    local d = math.min(math.abs(tod - 0.245), math.abs(tod - 0.775))
    dusk = clamp(1 - d / 0.06, 0, 1)
  end
  return a * (1 + 0.4 * dusk) * (1 - (wet or 0) / 0.3 * 0.5)
end
-- amount per second on a nose at speed (m/s): about 1/300 at 38 m/s in warm air
function M.bugRate(speed, airC, tod, wet)
  if (speed or 0) <= M.BUG_SPEED then return 0 end
  return (speed - M.BUG_SPEED) / 20 / 300 * M.bugActivity(airC, tod, wet)
end
-- the radius multiplier of a splat on a nose with this amount of bugs: later ones are bigger and overlap
function M.bugSize(amount) return 1 + 1.5 * clamp(amount or 0, 0, 1) end
-- rain loosens dried bugs slowly: wetSeconds of rain so far (0 = just started) scales the wash from a quarter to full over 90 s
function M.bugSoak(wetSeconds) return 0.25 + 0.75 * clamp((wetSeconds or 0) / 90, 0, 1) end

-- ---- dust. A film that climbs the body as it grows: the height (0..1 of the body) it reaches, and after rain how high the wash has cleared from the top down.
function M.dustHeight(amount) return clamp((amount or 0) ^ 0.7, 0, 1) end
-- the film above this height (0..1) is already gone after wetSeconds of rain; 1 = none washed
function M.dustWashHeight(wetSeconds) return clamp(1 - (wetSeconds or 0) / 60, 0, 1) end

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

-- One-time settings migration to version 2: the first start saved dirt build-up as off, a value the player never chose, and the default is on now. s is the settings file's
-- table, dirtSpeed the game setting csfxDirtSpeed (or nil). Returns: turn the build-up on, the dirtSpeed to write (or nil), whether the version moves up.
M.SETTINGS_VERSION = 2
function M.migrate(s, dirtSpeed)
  if (tonumber(s.settingsVersion) or 1) >= M.SETTINGS_VERSION then return false, nil, false end
  local on = type(s.mud) == 'table' and s.mud.buildup == false
  return on, (tonumber(dirtSpeed) == 0) and 1 or nil, true
end

-- snow weather: precipitation with the air below SNOW_AIR C (snowing 0..1), and whether it is warm enough to melt it
M.SNOW_AIR = 1.5
function M.snowing(drops, airC)
  if airC == nil or airC > M.SNOW_AIR then return 0 end
  return clamp((drops or 0) * 4, 0, 1)
end

-- washing: rain (wet 0..1, per second) and water (the share of the time a wheel was in water). Dust goes fast, mud and film slowly, rubber hardly at all.
local RAIN = { dust = 60, mud = 1200, grime = 3600, rubber = 6000, snow = 400, bugs = 500 }                -- seconds of full rain to wash a full amount off
local WATER = { dust = 3, mud = 12, grime = 40, rubber = 200, snow = 15, bugs = 30 }                   -- seconds in water
function M.dirtWash(d, dt, wet, water, wetSeconds)
  local out = {}
  for _, k in ipairs(M.KINDS) do
    local rain = (wet or 0) * dt / RAIN[k]
    if k == 'bugs' and wetSeconds then rain = rain * M.bugSoak(wetSeconds) end
    out[k] = clamp((d[k] or 0) - rain - (water or 0) * dt / WATER[k], 0, 1)
  end
  out.grime = clamp(out.grime + 0.3 * math.max(0, (d.dust or 0) - out.dust) * ((wet or 0) > 0 and 1 or 0), 0, M.CAP.grime)      -- washed dust leaves a streaky film
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
-- Lamps and their lenses are never touched: not by name, and not by an emissive or glow setting on the material.
local LAMP = { 'light', 'lamp', 'lens', 'signal', 'indicator', 'blinker', 'brake', 'reverse', 'fog', 'headl', 'taill', 'dome', 'beacon', 'strobe', 'led', 'beam', 'reflector', 'marker' }
-- how bright the day is, 0.04 at night to 1 at noon, in six steps (a change of the glass light costs a material reload, so it moves in steps): t = time of day 0..1 (0 = midnight, 0.5 = noon)
local LEVELS = { 0.04, 0.1, 0.25, 0.5, 0.75, 1 }
function M.sceneLight(t, rainy)
  if type(t) ~= 'number' then return 1 end
  local sun = math.max(0, math.sin((t - 0.25) * 2 * math.pi))                  -- 0 at six in the morning and evening, 1 at noon
  local b = 0.04 + 0.96 * sun ^ 0.6
  if rainy then b = b * 0.8 end
  local best = LEVELS[1]
  for _, l in ipairs(LEVELS) do if b >= l - 0.001 then best = l end end
  return best
end
function M.isLampName(name)
  local n = tostring(name):lower()
  for _, w in ipairs(LAMP) do if n:find(w, 1, true) then return true end end
  return false
end
function M.isEmissive(stages)
  for _, st in pairs(stages or {}) do
    if type(st) == 'table' then
      if set(st.emissiveMap) or tonumber(st.glow) and tonumber(st.glow) > 0 or tonumber(st.emissiveIntensityNits) and tonumber(st.emissiveIntensityNits) > 0 then return true end
      local ef = tostring(st.emissiveFactor or '')
      for x in ef:gmatch('%S+') do if (tonumber(x) or 0) > 0.001 then return true end end
    end
  end
  return false
end
function M.isGlassName(name)
  local n = tostring(name):lower()
  return M.isLampName(n) == false and not n:find('_on$') and not n:find('_on_', 1, true) and n:find('glass', 1, true) ~= nil and not n:find('dmg', 1, true) and not n:find('broken', 1, true) and not n:find('invisible', 1, true) and not n:find('crack', 1, true)
end

-- The glass takes its water from a per-car, per-material web canvas (vehicles/common/carSurfaceFx/glass.html) named '@csfx_<material>': the engine resolves a '@tag'
-- texture only in the colour-type slots (baseColorMap, emissiveMap...), while a normal map or detail map name gets the material's folder put in front of it and fails.
-- So the canvas REPLACES the glass's own base colour map: the page draws that image first (the original path is in its URL) and the drops on top.
function M.glassTag(name) return '@csfx_' .. tostring(name):gsub('[^%w_]', '_') end

-- The inside glass (name ends in 'int') is clear, so a colour change on it is invisible, and the engine does not resolve a '@tag' in its opacity map (tried): its EMISSIVE map
-- becomes the canvas instead (light adds to the picture whatever the glass opacity is; the page draws only the glints and bright rims).
M.insideMode = 'emissive'                                         -- or 'color' (carSurfaceFx.insideMode): which slot the inside glass's canvas goes in
M.outsideMode = 'emissive'                                           -- the outside glass: 'color' (the canvas replaces the tint map; the game's tint image cannot be read by the page, a flat dark tint stands in) or 'emissive' (glints and rims only, the glass keeps its own look)
function M.glassMode(name) return tostring(name):lower():find('int$') and M.insideMode or M.outsideMode end

-- the map the canvas replaces and the original image under the drops: field, path (nil when the canvas has no image under it, as with light only)
function M.glassMap(st, mode)
  if mode == 'emissive' then return 'emissiveMap', nil end
  if not set(st.baseColorMap) then return nil end                 -- no tint map to draw under the drops: leave this glass alone
  return 'baseColorMap', st.baseColorMap
end

M.glassEmissive = 1.0                                             -- how bright the drops glint (emissiveFactor)
M.glassLight = 1                                                  -- 0..1: how bright the scene is (set from the time of day): the glints are bright by day and faint at night
M.glassNits = 22000                                               -- and how strong that light is (emissiveIntensityNits): the engine's default is far too faint to see in daylight (a solid white canvas showed as a faint haze at 1500; hazy at 6000, milky at 25000, solid white at 100000, measured on the covet's side windows by day, so the thin drops need about 40000)
function M.glassFields(st, tag, mode)
  local field = M.glassMap(st, mode or 'color')
  if not field then return {} end
  local out = { [field] = tag }
  if mode == 'emissive' then
    out.emissiveFactor = string.format('%.2f %.2f %.2f', M.glassEmissive, M.glassEmissive, M.glassEmissive)
    out.emissiveIntensityNits = string.format('%.0f', M.glassNits * M.glassLight)
  end
  return out
end

-- (x, y): the direction that is DOWN the glass in the glass material's UV space; differs per car, set with carSurfaceFx.tuneGlass
M.glassAxis = { x = 0, y = 1 }
M.glassTint, M.glassPasses = 0.5, 1                             -- colour glass: how dark the tint is drawn, how often the image is squared (see glass.js)
M.glassSize = 3.0                                          -- drop size and density on the window canvas (a window covers only part of the texture)

return M
