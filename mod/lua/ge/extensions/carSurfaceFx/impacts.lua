-- Car Surface FX: crashes (port P9-P11, written fresh; the features follow Connor's Surface FX): glass shard piles where a window broke, pieces of trim, plastic and metal thrown off by
-- a joint giving way or a hard hit (they fly, bounce, settle on the road and are cleaned up after a time or a distance), and sparks where metal grinds on a hard surface.
-- The car side (lua/vehicle/extensions/carSurfaceFxImpacts.lua, through the shared carSurfaceFxContact) detects and calls glass(), debris() and sparks() here. Piles and settled pieces are
-- decals drawn through marks.drawBatch (the one seam where the scene light goes); flying pieces and sparks are a few debug-drawer shapes with small caps. Rules: impactrules.lua (tested).
local M = {}

local rules = require('carSurfaceFx/impactrules')

local TAG = 'carSurfaceFx_impacts'
local SETTINGS_FILE = 'settings/carSurfaceFx_impacts.json'
local DEPTH = 1.5
local GLASS_TEX = 'art/decals/impacts/shards_%d.png'
local CHIP_TEX = 'art/decals/impacts/chip_%d.png'

local settings = rules.defaults()
local piles, pileHead, pileN = {}, 0, 0                          -- shard piles (ring)
local flying, flyN = {}, 0                                        -- pieces in the air
local resting, restHead, restN = {}, 0, 0                         -- settled pieces (ring)
local sparksList, sparkN = {}, 0
local pools = {}
local chipColor, sparkPalette, flyColor = {}, {}, {}
local dirty, lastSave = false, 0
local injectT, ageT = 0, 0
local counts = { glass = 0, debris = 0, sparks = 0 }            -- how many calls came in (QA reads them)

local clamp = rules.clamp
local function mergeInto(dst, src)
  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then mergeInto(dst[k], v) elseif type(v) == type(dst[k]) then dst[k] = v end
  end
end

function M.defaults() return rules.defaults() end
function M.settings() return settings end

local function rebuild()
  chipColor, flyColor = {}, {}
  if ColorF then
    for _, k in ipairs(rules.DEBRIS) do
      local c = settings.debris.colors[k] or { 0.4, 0.4, 0.4 }
      flyColor[k] = ColorF(c[1], c[2], c[3], 1)
    end
    local s = settings.sparks.color
    sparkPalette = {}
    for i = 1, 8 do
      local g = i / 8
      sparkPalette[i] = ColorF(s[1], s[2] * (0.5 + 0.5 * g), s[3] * g, 0.25 + 0.75 * g)
    end
  end
end

function M.save() pcall(jsonWriteFile, SETTINGS_FILE, settings, true) dirty = false lastSave = os.clock() end
function M.load()
  settings = rules.defaults()
  local ok, saved = pcall(jsonReadFile, SETTINGS_FILE)
  if ok and type(saved) == 'table' then mergeInto(settings, saved) end
  rebuild()
end

local function walk(path)
  local t, parts = settings, {}
  for part in tostring(path):gmatch('[^%.]+') do parts[#parts + 1] = part end
  for i = 1, #parts - 1 do
    t = type(t) == 'table' and t[parts[i]] or nil
    if type(t) ~= 'table' then return nil end
  end
  local key = parts[#parts]
  if type(t) ~= 'table' or t[key] == nil then return nil end
  return t, key
end
function M.get(path) local t, k = walk(path) if t then return t[k] end return nil end

-- ---- the cars that report: the player's, and the nearest others
local function reporters()
  local out = {}
  local pv = be:getPlayerVehicleID(0)
  local pvObj = pv and pv >= 0 and be:getObjectByID(pv)
  if pvObj then out[pv] = true end
  if settings.others.enabled and pvObj then
    local pp, r2, list = pvObj:getPosition(), settings.others.range * settings.others.range, {}
    for i = 0, be:getObjectCount() - 1 do
      local o = be:getObject(i)
      if o and o:getID() ~= pv then
        local p = o:getPosition()
        local dx, dy = p.x - pp.x, p.y - pp.y
        if dx * dx + dy * dy <= r2 then list[#list + 1] = { o:getID(), dx * dx + dy * dy } end
      end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, math.min(#list, settings.others.maxCars) do out[list[i][1]] = true end
  end
  return out
end

local function pushConfig(veh, emit)
  local g, d, s = settings.glass.enabled, settings.debris.enabled, settings.sparks.enabled
  veh:queueLuaCommand(string.format('if not carSurfaceFxImpacts then extensions.load("carSurfaceFxImpacts") end carSurfaceFxImpacts.setConfig(%s, %s, %s, {glassMinEnergy=%d, clusterRadius=%.2f, idle=%.2f, impactSpeed=%.1f, jointChance=%.2f, boltChance=%.2f, sparkMinSpeed=%.1f, sparkMinForce=%d})',
    (emit and g) and 'true' or 'false', (emit and d) and 'true' or 'false', (emit and s) and 'true' or 'false', settings.glass.minEnergy, settings.glass.clusterRadius, settings.glass.idle,
    settings.debris.impactSpeed, settings.debris.jointChance, settings.debris.boltChance, settings.sparks.minSpeed, settings.sparks.minForce))
end
local function injectAll()
  local who = reporters()
  for _, v in ipairs(getAllVehicles()) do pushConfig(v, settings.enabled and who[v:getID()] == true) end
end

function M.configure(s)
  if type(s) == 'table' then mergeInto(settings, s) end
  rebuild()
  pools = {}
  dirty = true
  pcall(injectAll)
end
function M.set(path, value)
  local t, k = walk(path)
  if not t or type(value) ~= type(t[k]) then return false end
  t[k] = value
  M.configure()
  return true
end
function M.reload() M.load() M.configure() end

-- ---- the ground under a point
local function groundZ(x, y, z)
  local d
  pcall(function() d = castRayStatic(vec3(x, y, z + 0.8), vec3(0, 0, -1), 6) end)
  if d and d >= 0 and d < 6 then return z + 0.8 - d end
  return nil
end

-- ---- glass
function M.glass(vid, x, y, z, sev)
  counts.glass = counts.glass + 1
  if not (settings.enabled and settings.glass.enabled) then return end
  local gz = groundZ(x, y, z)
  if not gz then return end
  local maxN = math.max(4, math.floor(settings.glass.maxPiles))
  pileHead = (pileHead % maxN) + 1
  local p = piles[pileHead] or {}
  p.x, p.y, p.z, p.r, p.angle, p.variant = x, y, gz, rules.pileRadius(sev, settings.glass.size), math.random() * 6.2832, 1 + math.random(0, 2)
  piles[pileHead] = p
  if pileN < maxN then pileN = pileN + 1 end
end

-- ---- debris: a burst at a node of a car
function M.debris(vid, x, y, z, vx, vy, vz, kind, hard, spread)
  counts.debris = counts.debris + 1
  local cfg = settings.debris
  if not (settings.enabled and cfg.enabled) then return end
  local n = rules.pieces(kind, hard, cfg)
  local gz = groundZ(x, y, z)
  if not gz then return end
  for _ = 1, n do
    if flyN >= cfg.maxFlying then break end
    flyN = flyN + 1
    local p = flying[flyN] or {}
    local sp = 1 + (spread or 0.15) * 14
    p.x, p.y, p.z = x + (math.random() - 0.5) * 0.2, y + (math.random() - 0.5) * 0.2, z
    p.vx, p.vy, p.vz = vx * 0.5 + (math.random() - 0.5) * sp, vy * 0.5 + (math.random() - 0.5) * sp, math.max(0.5, vz * 0.3) + math.random() * sp * 0.6
    p.kind, p.size, p.rest, p.gz = kind, (0.6 + math.random() * 0.8) * cfg.size, false, gz
    p.angle, p.born, p.variant = math.random() * 6.2832, 0, 1 + math.random(0, 1)
    flying[flyN] = p
  end
end

local function settle(p)
  local maxN = math.max(8, math.floor(settings.debris.maxResting))
  restHead = (restHead % maxN) + 1
  local r = resting[restHead] or {}
  r.x, r.y, r.z, r.kind, r.size, r.angle, r.variant, r.born = p.x, p.y, p.gz, p.kind, p.size, p.angle, p.variant, 0
  r.alive = true
  resting[restHead] = r
  if restN < maxN then restN = restN + 1 end
end

-- ---- sparks
function M.sparks(x, y, z, vx, vy, vz, force)
  counts.sparks = counts.sparks + 1
  local cfg = settings.sparks
  if not (settings.enabled and cfg.enabled) then return end
  local n = rules.sparkCount(force, cfg)
  for _ = 1, n do
    if sparkN >= cfg.maxSparks then break end
    sparkN = sparkN + 1
    local s = sparksList[sparkN]
    if not s then s = { a = vec3(0, 0, 0), b = vec3(0, 0, 0) } sparksList[sparkN] = s end
    local sp = 2 + math.random() * 4
    s.x, s.y, s.z = x, y, z
    s.px, s.py, s.pz = x, y, z
    s.vx, s.vy, s.vz = vx * 0.3 + (math.random() - 0.5) * sp, vy * 0.3 + (math.random() - 0.5) * sp, math.random() * sp * 0.8
    s.life, s.age = cfg.life * (0.6 + math.random() * 0.6), 0
  end
end

-- ---- drawing
local function slot(pool, i)
  local e = pool[i]
  if not e then
    e = { texture = GLASS_TEX:format(1), position = vec3(0, 0, 0), forwardVec = vec3(1, 0, 0), color = ColorF(1, 1, 1, 1), scale = vec3(0.2, 0.2, DEPTH),
      fadeStart = settings.cullRadius * 0.8, fadeEnd = settings.cullRadius }
    pool[i] = e
  end
  return e
end
local function draw(pool, n)
  local marks = rawget(_G, 'carSurfaceFx_marks')
  if marks and marks.drawBatch then marks.drawBatch(pool, n)
  elseif Engine and Engine.Render and Engine.Render.DynamicDecalMgr then Engine.Render.DynamicDecalMgr.addDecals(pool, n) end
end

local function colorOf(key, c, a)
  local col = chipColor[key]
  if not col then col = ColorF(c[1], c[2], c[3], a) chipColor[key] = col end
  return col
end

function M.onPreRender(dt)
  if not settings.enabled then return end
  local hasDecals = pileN > 0 or restN > 0
  local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
  local camX, camY = cam and cam.x, cam and cam.y
  local cr2 = settings.cullRadius * settings.cullRadius
  if hasDecals and Engine and Engine.Render and Engine.Render.DynamicDecalMgr then
    if pileN > 0 and settings.glass.enabled then
      local gc = settings.glass.color
      local color = colorOf('glass', gc, settings.glass.opacity)
      for v = 1, 3 do
        local pool, n = pools['g' .. v], 0
        if not pool then pool = {} pools['g' .. v] = pool end
        for i = 1, pileN do
          local p = piles[i]
          if p and p.variant == v and (not camX or (p.x - camX) ^ 2 + (p.y - camY) ^ 2 <= cr2) then
            n = n + 1
            local e = slot(pool, n)
            e.texture = GLASS_TEX:format(v)
            e.position:set(p.x, p.y, p.z)
            e.forwardVec:set(math.cos(p.angle), math.sin(p.angle), 0)
            e.scale:set(p.r * 2, p.r * 2, DEPTH)
            e.color = color
          end
        end
        if n > 0 then draw(pool, n) end
      end
    end
    if restN > 0 and settings.debris.enabled then
      for _, kind in ipairs(rules.DEBRIS) do
        local c = settings.debris.colors[kind]
        local color = colorOf('r' .. kind, c, 0.95)
        for v = 1, 2 do
          local pool, n = pools['d' .. kind .. v], 0
          if not pool then pool = {} pools['d' .. kind .. v] = pool end
          for i = 1, restN do
            local p = resting[i]
            if p and p.alive and p.kind == kind and p.variant == v and (not camX or (p.x - camX) ^ 2 + (p.y - camY) ^ 2 <= cr2) then
              n = n + 1
              local e = slot(pool, n)
              e.texture = CHIP_TEX:format(v)
              e.position:set(p.x, p.y, p.z)
              e.forwardVec:set(math.cos(p.angle), math.sin(p.angle), 0)
              e.scale:set(0.07 * p.size, 0.05 * p.size, DEPTH)
              e.color = color
            end
          end
          if n > 0 then draw(pool, n) end
        end
      end
    end
  end
  if flyN > 0 and debugDrawer and flyColor.metal then
    for i = 1, flyN do
      local p = flying[i]
      if not p.pos then p.pos = vec3(0, 0, 0) end
      p.pos:set(p.x, p.y, p.z)
      pcall(debugDrawer.drawSphere, debugDrawer, p.pos, 0.02 + 0.015 * p.size, flyColor[p.kind] or flyColor.metal)
    end
  end
  if sparkN > 0 and debugDrawer and sparkPalette[1] then
    for i = 1, sparkN do
      local s = sparksList[i]
      s.a:set(s.px, s.py, s.pz)
      s.b:set(s.x, s.y, s.z)
      local lvl = clamp(math.floor(rules.sparkGlow(s, settings.sparks.brightness) * 8 + 0.5), 1, 8)
      pcall(debugDrawer.drawLine, debugDrawer, s.a, s.b, sparkPalette[lvl])
    end
  end
end

-- ---- the world moves on
function M.onUpdate(dt)
  -- flying pieces
  local i = 1
  while i <= flyN do
    local p = flying[i]
    if rules.step(p, dt, p.gz, settings.debris.bounce, settings.debris.friction) then
      settle(p)
      flying[i], flying[flyN] = flying[flyN], p
      flyN = flyN - 1
    else
      i = i + 1
    end
  end
  -- sparks
  i = 1
  while i <= sparkN do
    local s = sparksList[i]
    if rules.sparkStep(s, dt) then
      sparksList[i], sparksList[sparkN] = sparksList[sparkN], s
      sparkN = sparkN - 1
    else
      i = i + 1
    end
  end
  ageT = ageT + dt
  if ageT >= 1 then
    ageT = 0
    -- cleaned up after a time or a distance
    local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
    local d2 = settings.debris.clearDistance * settings.debris.clearDistance
    for k = 1, restN do
      local r = resting[k]
      if r and r.alive then
        r.born = r.born + 1
        if r.born > settings.debris.life or (cam and (r.x - cam.x) ^ 2 + (r.y - cam.y) ^ 2 > d2) then r.alive = false end
      end
    end
  end
  injectT = injectT + dt
  if injectT >= 2 then injectT = 0 pcall(injectAll) end
  if dirty and os.clock() - lastSave > 1 then M.save() end
end

function M.clear() piles, pileHead, pileN, flying, flyN, resting, restHead, restN, sparksList, sparkN = {}, 0, 0, {}, 0, {}, 0, 0, {}, 0 counts = { glass = 0, debris = 0, sparks = 0 } end
function M.pileCount() return pileN end
function M.flyingCount() return flyN end
function M.restingCount() local n = 0 for i = 1, restN do if resting[i] and resting[i].alive then n = n + 1 end end return n end
function M.sparkCount() return sparkN end

-- ---- QA
function M.status()
  return string.format('piles %d flying %d resting %d sparks %d calls glass %d debris %d sparks %d', pileN, flyN, M.restingCount(), sparkN, counts.glass, counts.debris, counts.sparks)
end

-- put each effect down in front of the player's car by hand (to see how it is drawn): glass, debris, sparks
function M.test(what)
  local veh = be:getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  local p, d = veh:getPosition(), veh:getDirectionVector()
  local x, y, z = p.x + d.x * 6, p.y + d.y * 6, p.z + 0.8
  if what == 'glass' then M.glass(0, x, y, z, 1) M.glass(0, x + 1.2, y + 0.6, z, 0.4) return 'glass piles put down'
  elseif what == 'debris' then
    for _, k in ipairs(rules.DEBRIS) do M.debris(0, x, y, z + 0.5, d.x * 2, d.y * 2, 1, k, true, 0.3) end
    return 'debris thrown'
  elseif what == 'sparks' then for _ = 1, 8 do M.sparks(x, y, z - 0.3, d.x * 3, d.y * 3, 0, 4000) end return 'sparks thrown'
  end
  return 'use glass, debris or sparks'
end

-- a real window break on the player's car: every window beam is broken through the engine's own call, so the whole chain (the break, the detection, the pile) is what runs
function M.breakWindows()
  local veh = be:getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  veh:queueLuaCommand('if carSurfaceFxImpacts then carSurfaceFxImpacts.breakWindows() end')
  return 'window break asked'
end

function M.onVehicleSpawned() pcall(injectAll) end
function M.onVehicleSwitched() pcall(injectAll) end
function M.onExtensionLoaded() M.load() M.clear() pools = {} pcall(injectAll) end
function M.onExtensionUnloaded()
  pcall(function()
    for _, v in ipairs(getAllVehicles()) do v:queueLuaCommand('if carSurfaceFxImpacts then carSurfaceFxImpacts.setConfig(false, false, false) end') end
  end)
end
function M.onClientStartMission() M.clear() pcall(injectAll) end
function M.onClientEndMission() M.clear() end

M.TAG = TAG
return M
