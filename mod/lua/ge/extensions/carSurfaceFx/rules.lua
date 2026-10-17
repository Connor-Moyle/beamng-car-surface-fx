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
    out.detailNormalMap = M.DROPLETS
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
  local c = p.baseColor
  local tint = {}
  for i = 1, 3 do tint[i] = DUST[i] + (MUD[i] - DUST[i]) * d end
  local function mix(a, b) return a + (b - a) * k end
  return { baseColor = { mix(c[1], tint[1]), mix(c[2], tint[2]), mix(c[3], tint[3]), c[4] or 1 }, metallic = (p.metallic or 0) * (1 - 0.8 * k),
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

-- ---------------------------------------------------------------------------------------------------------------------
-- Windscreen drops: a fixed pool in screen fractions (x 0..1 left to right, y 0..1 top to bottom, r in screen heights). Pure, so it is tested here.
-- ---------------------------------------------------------------------------------------------------------------------
M.POOL = 150
local SLIDE_R = 0.008                                   -- drops bigger than this run down the glass

function M.dropsNew()
  local d = { n = M.POOL, x = {}, y = {}, r = {}, alive = {}, sweep = 0, t = 0 }
  for i = 1, M.POOL do d.x[i], d.y[i], d.r[i], d.alive[i] = 0, 0, 0, false end
  return d
end

local function free(d)
  for i = 1, d.n do if not d.alive[i] then return i end end
end

-- add a drop; one that lands on another merges into it (areas add)
function M.dropAdd(d, x, y, r)
  for i = 1, d.n do
    if d.alive[i] then
      local dx, dy = d.x[i] - x, d.y[i] - y
      local rr = d.r[i] + r
      if dx * dx + dy * dy < rr * rr then
        local nr = math.sqrt(d.r[i] * d.r[i] + r * r)
        d.x[i], d.y[i], d.r[i] = (d.x[i] * d.r[i] + x * r) / (d.r[i] + r), (d.y[i] * d.r[i] + y * r) / (d.r[i] + r), nr
        return i
      end
    end
  end
  local i = free(d)
  if not i then return nil end
  d.x[i], d.y[i], d.r[i], d.alive[i] = x, y, r, true
  return i
end

-- rain 0..1 (falling now), speed m/s, wiper 0..1 (0 off), rnd() -> 0..1
function M.dropsStep(d, dt, rain, speed, wiper, rnd)
  d.t = d.t + dt
  local spawns = rain * 60 * (0.5 + clamp(speed / 30, 0, 1)) * dt
  while spawns > 0 do
    if spawns >= 1 or rnd() < spawns then
      local q = rnd()
      M.dropAdd(d, rnd(), rnd() * 0.95, 0.003 + 0.007 * q * q)
    end
    spawns = spawns - 1
  end
  local push = (speed / 40) * (speed / 40) * 0.12                       -- air pushes drops up the glass
  for i = 1, d.n do
    if d.alive[i] then
      local r = d.r[i]
      local vy = (r > SLIDE_R and 0.03 * (r / SLIDE_R) * (r / SLIDE_R) or 0) - (r > 0.005 and push or (speed > 8 and push * 0.5 or 0))
      d.y[i] = d.y[i] + vy * dt
      if r > SLIDE_R then d.x[i] = d.x[i] + (rnd() - 0.5) * 0.01 * dt end
      if d.y[i] > 1.05 or d.y[i] < -0.05 then d.alive[i] = false end
    end
  end
  if wiper > 0.05 then                                                   -- the blade sweeps left-right-left; whatever it crosses is wiped
    local phase = (d.t * wiper * 0.9) % 2
    local pos = phase < 1 and phase or 2 - phase
    local lo, hi = math.min(d.sweep, pos), math.max(d.sweep, pos)
    for i = 1, d.n do
      if d.alive[i] and d.x[i] >= lo - 0.02 and d.x[i] <= hi + 0.02 and d.y[i] > 0.15 then d.alive[i] = false end
    end
    d.sweep = pos
  end
end

return M
