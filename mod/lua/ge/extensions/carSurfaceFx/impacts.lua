-- Car Surface FX: crashes (port P9-P11, written fresh; the features follow Connor's Surface FX): glass shard piles where a window broke, pieces of trim, plastic and metal thrown off by
-- a joint giving way or a hard hit (they settle on the road and are cleaned up after a time or a distance), and sparks where metal grinds on a hard surface.
-- The car side (lua/vehicle/extensions/carSurfaceFxImpacts.lua, through the shared carSurfaceFxContact) detects, throws the visible part with the GAME'S OWN particle emitters (the spark
-- particle of metal on asphalt, the plastic chunk and glass particles its beams throw) and calls glass(), debris() and sparks() here. This module keeps what stays: shard piles and settled
-- pieces are decals drawn through marks.drawBatch (the one seam where the scene light goes); a piece is followed through its flight (invisible, a point mass) to know where it lands.
-- Rules: impactrules.lua (tested).
local M = {}

local rules = require('carSurfaceFx/impactrules')
local texlist = require('carSurfaceFx/texlist')

local TAG = 'carSurfaceFx_impacts'
local SETTINGS_FILE = 'settings/carSurfaceFx_impacts.json'
local DEPTH = 1.5
local DIR = 'art/decals/impacts/'
local shardList = { 'shards_1.png', 'shards_2.png', 'shards_3.png' }      -- the pictures of the folder (rescanned: a png dropped in shows up)
local chipList = { 'chip_1.png', 'chip_2.png' }

local settings = rules.defaults()
local piles, pileHead, pileN = {}, 0, 0                          -- shard piles (ring)
local flying, flyN = {}, 0                                        -- pieces in the air (not drawn: the particles are the car side's)
local resting, restHead, restN = {}, 0, 0                         -- settled pieces (ring)
local pools = {}
local chipColor = {}
local dirty, lastSave = false, 0
local injectT, ageT = 0, 0
local counts = { glass = 0, debris = 0, sparks = 0 }            -- how many calls came in (QA reads them)

local clamp = rules.clamp
local function mergeInto(dst, src)
  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then mergeInto(dst[k], v) elseif type(v) == type(dst[k]) then dst[k] = v end
  end
end

-- the pictures: every png in the folder whose name starts with shards / chip (the player's own too)
function M.rescan()
  local s, c = texlist.scan(DIR, 'shards'), texlist.scan(DIR, 'chip')
  if #s > 0 then shardList = s end
  if #c > 0 then chipList = c end
  pools = {}
  return shardList, chipList
end
function M.variants() return shardList, chipList end

function M.defaults() return rules.defaults() end
function M.settings() return settings end

function M.save() pcall(jsonWriteFile, SETTINGS_FILE, settings, true) dirty = false lastSave = os.clock() end
function M.load()
  settings = rules.defaults()
  local ok, saved = pcall(jsonReadFile, SETTINGS_FILE)
  if ok and type(saved) == 'table' then mergeInto(settings, saved) end
  chipColor = {}
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
  veh:queueLuaCommand(string.format('if not carSurfaceFxImpacts then extensions.load("carSurfaceFxImpacts") end carSurfaceFxImpacts.setConfig(%s, %s, %s, {glassMinEnergy=%d, clusterRadius=%.2f, idle=%.2f, impactSpeed=%.1f, jointChance=%.2f, boltChance=%.2f, sparkMinSpeed=%.1f, sparkMinForce=%d, sparkAmount=%.2f, debrisAmount=%.2f, particles=%d})',
    (emit and g) and 'true' or 'false', (emit and d) and 'true' or 'false', (emit and s) and 'true' or 'false', settings.glass.minEnergy, settings.glass.clusterRadius, settings.glass.idle,
    settings.debris.impactSpeed, settings.debris.jointChance, settings.debris.boltChance, settings.sparks.minSpeed, settings.sparks.minForce, settings.sparks.amount, settings.debris.amount,
    settings.debris.particles and 1 or 0))
end
local function injectAll()
  local who = reporters()
  for _, v in ipairs(getAllVehicles()) do pushConfig(v, settings.enabled and who[v:getID()] == true) end
end

function M.configure(s)
  if type(s) == 'table' then mergeInto(settings, s) end
  chipColor = {}
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
  -- a window sits above the car, so straight down is under the car where nobody sees the glass: it falls out to the side, a metre or so from the car's centre line
  local veh = getObjectByID(vid)
  local cp = veh and veh:getPosition()
  if cp then
    local dx, dy = x - cp.x, y - cp.y
    local len = math.sqrt(dx * dx + dy * dy)
    local ux, uy = 0, 0
    if len > 0.3 then ux, uy = dx / len, dy / len else local a = math.random() * 6.2832 ux, uy = math.cos(a), math.sin(a) end
    x, y = x + ux * 1.0, y + uy * 1.0
  end
  local gz = groundZ(x, y, z)
  if not gz then return end
  local maxN = math.max(4, math.floor(settings.glass.maxPiles))
  pileHead = (pileHead % maxN) + 1
  local p = piles[pileHead] or {}
  p.x, p.y, p.z, p.r, p.angle, p.seed = x, y, gz, rules.pileRadius(sev, settings.glass.size), math.random() * 6.2832, math.random()
  piles[pileHead] = p
  if pileN < maxN then pileN = pileN + 1 end
end

-- ---- debris: a burst at a node of a car; the pieces are followed to where they land
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
    p.angle, p.born, p.seed = math.random() * 6.2832, 0, math.random()
    flying[flyN] = p
  end
end

local function settle(p)
  local maxN = math.max(8, math.floor(settings.debris.maxResting))
  restHead = (restHead % maxN) + 1
  local r = resting[restHead] or {}
  r.x, r.y, r.z, r.kind, r.size, r.angle, r.seed, r.born = p.x, p.y, p.gz, p.kind, p.size, p.angle, p.seed, 0
  r.alive = true
  resting[restHead] = r
  if restN < maxN then restN = restN + 1 end
end

-- ---- sparks: thrown by the game's own spark particle on the car side; here only the count (QA)
function M.sparks() counts.sparks = counts.sparks + 1 end

-- ---- drawing: the decals only
local function slot(pool, i)
  local e = pool[i]
  if not e then
    e = { texture = DIR .. shardList[1], position = vec3(0, 0, 0), forwardVec = vec3(1, 0, 0), color = ColorF(1, 1, 1, 1), scale = vec3(0.2, 0.2, DEPTH),
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
  if pileN == 0 and restN == 0 then return end
  if not (Engine and Engine.Render and Engine.Render.DynamicDecalMgr) then return end
  local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
  local camX, camY = cam and cam.x, cam and cam.y
  local cr2 = settings.cullRadius * settings.cullRadius
  if pileN > 0 and settings.glass.enabled then
    local color = colorOf('glass', settings.glass.color, settings.glass.opacity)
    local shown = texlist.shown(shardList, settings.glass.texture)
    for v = 1, #shown do
      local pool, n = pools['g' .. v], 0
      if not pool then pool = {} pools['g' .. v] = pool end
      for i = 1, pileN do
        local p = piles[i]
        if p and texlist.indexFor(#shown, p.seed) == v and (not camX or (p.x - camX) ^ 2 + (p.y - camY) ^ 2 <= cr2) then
          n = n + 1
          local e = slot(pool, n)
          e.texture = DIR .. shown[v]
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
      local color = colorOf('r' .. kind, settings.debris.colors[kind], 0.95)
      local shownChips = texlist.shown(chipList, settings.debris.texture)
      for v = 1, #shownChips do
        local pool, n = pools['d' .. kind .. v], 0
        if not pool then pool = {} pools['d' .. kind .. v] = pool end
        for i = 1, restN do
          local p = resting[i]
          if p and p.alive and p.kind == kind and texlist.indexFor(#shownChips, p.seed) == v and (not camX or (p.x - camX) ^ 2 + (p.y - camY) ^ 2 <= cr2) then
            n = n + 1
            local e = slot(pool, n)
            e.texture = DIR .. shownChips[v]
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

-- ---- the world moves on
function M.onUpdate(dt)
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

function M.clear() piles, pileHead, pileN, flying, flyN, resting, restHead, restN = {}, 0, 0, {}, 0, {}, 0, 0 counts = { glass = 0, debris = 0, sparks = 0 } end
function M.pileCount() return pileN end
function M.flyingCount() return flyN end
function M.restingCount() local n = 0 for i = 1, restN do if resting[i] and resting[i].alive then n = n + 1 end end return n end
function M.callCount(kind) return counts[kind] or 0 end

-- ---- QA
function M.status()
  return string.format('piles %d flying %d resting %d calls glass %d debris %d sparks %d', pileN, flyN, M.restingCount(), counts.glass, counts.debris, counts.sparks)
end

-- put each effect down in front of the player's car by hand (to see how it is drawn): glass, debris (settled pieces), sparks (the game's spark particles from the car's front)
function M.test(what)
  local veh = be:getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  local p, d = veh:getPosition(), veh:getDirectionVector()
  local x, y, z = p.x + d.x * 6, p.y + d.y * 6, p.z + 0.8
  if what == 'glass' then M.glass(0, x, y, z, 1) M.glass(0, x + 1.2, y + 0.6, z, 0.4) return 'glass piles put down'
  elseif what == 'debris' then
    for _, k in ipairs(rules.DEBRIS) do M.debris(0, x, y, z + 0.5, d.x * 2, d.y * 2, 1, k, true, 0.3) end
    veh:queueLuaCommand('if carSurfaceFxImpacts then carSurfaceFxImpacts.test("debris") end')
    return 'debris thrown'
  elseif what == 'sparks' then
    veh:queueLuaCommand('if carSurfaceFxImpacts then carSurfaceFxImpacts.test("sparks") end')
    return 'sparks asked'
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
function M.onExtensionLoaded() M.load() M.clear() M.rescan() pcall(injectAll) end
function M.onExtensionUnloaded()
  pcall(function()
    for _, v in ipairs(getAllVehicles()) do v:queueLuaCommand('if carSurfaceFxImpacts then carSurfaceFxImpacts.setConfig(false, false, false) end') end
  end)
end
function M.onClientStartMission() M.clear() pcall(injectAll) end
function M.onClientEndMission() M.clear() end

M.TAG = TAG
require('carSurfaceFx/guard').wrap(M, 'carSurfaceFx_impacts', { 'onPreRender', 'onUpdate' })
return M
