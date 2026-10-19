-- Car Surface FX: wheel ruts in soft ground (port P4, written fresh; the feature follows Connor's Surface FX): a car pressing mud, snow, sand, dirt or gravel leaves a rut with raised lips that
-- is deeper the heavier the wheel's load and the softer the ground, and that deepens (a few stacked layers) when the same track is driven again.
-- The car side (lua/vehicle/extensions/carSurfaceFxRuts.lua) sends a sample of each loaded wheel's path every 0.6 m; here the path is cut into chunks, and each chunk is a small DecalRoad with
-- connor-19's lit mark materials (csfx_rut_<kind>_dry / _wet, art/surfacefx/marks, made sure by carSurfaceFx/markMaterials) - lit by the scene, glossy when wet. If a DecalRoad cannot be made
-- the module falls back (once, one log line) to ground decals drawn through marks.drawBatch with art/decals/ruts/rut.png, so the tab works whatever the road route does.
-- Rules: rutrules.lua (tested).
local M = {}

local rules = require('carSurfaceFx/rutrules')
local berm = require('carSurfaceFx/berm')

local TAG = 'carSurfaceFx_ruts'
local SETTINGS_FILE = 'settings/carSurfaceFx_ruts.json'
local DEPTH = 1.5
local RUT_TEX = 'art/decals/ruts/rut.png'
local COLORS = { mud = { 0.10, 0.07, 0.05 }, snow = { 0.55, 0.60, 0.68 }, sand = { 0.50, 0.42, 0.28 }, dirt = { 0.22, 0.15, 0.09 }, gravel = { 0.28, 0.27, 0.25 } }

local settings = rules.defaults()
local paths = {}                                                  -- 'vid:wheel' -> a collected path
local pending, pendingN = {}, 0                                   -- chunks waiting for the budget
local roads, roadHead, roadN = {}, 0, 0                           -- the DecalRoads made (a ring of object ids)
local segs, segHead, segN = {}, 0, 0                              -- the fallback: decal segments (a ring)
local grid = rules.newGrid()
local bucket = {}
local mode                                                        -- 'road' or 'decal' now (the setting, or the fallback after a failure)
local fellBack = false
local wasWet = false
local pool = {}
local dirty, lastSave = false, 0
local injectT, idleT = 0, 0
local made = { roads = 0, segments = 0, skipped = 0 }
local ticks = 0                                                   -- onUpdate calls (QA: 0 after a while means the engine is not calling the hook)
local forceKind
local sizes = {}                                                  -- kind -> { width, length } from the mark materials index
local colorCache = {}

local clamp = rules.clamp
local function mergeInto(dst, src)
  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then mergeInto(dst[k], v) elseif type(v) == type(dst[k]) then dst[k] = v end
  end
end

function M.defaults() return rules.defaults() end
function M.settings() return settings end

function M.save() pcall(jsonWriteFile, SETTINGS_FILE, settings, true) dirty = false lastSave = os.clock() end
function M.load()
  settings = rules.defaults()
  local ok, saved = pcall(jsonReadFile, SETTINGS_FILE)
  if ok and type(saved) == 'table' then mergeInto(settings, saved) end
  mode = settings.routing == 'decal' and 'decal' or 'road'
  fellBack = false
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

-- ---- the cars that report
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
  veh:queueLuaCommand(string.format('if not carSurfaceFxRuts then extensions.load("carSurfaceFxRuts") end carSurfaceFxRuts.setConfig(%s, %.2f, %d)',
    emit and 'true' or 'false', settings.step, 150))
  local okS, lit = pcall(function() return require('carSurfaceFx/surfaces').literalNow() end)      -- the map's own ground materials (P12)
  if okS and lit and lit ~= '{}' then veh:queueLuaCommand('if carSurfaceFxRuts then carSurfaceFxRuts.setMaterials(' .. lit .. ') end') end
end
local function injectAll()
  local who = reporters()
  for _, v in ipairs(getAllVehicles()) do pushConfig(v, settings.enabled and who[v:getID()] == true) end
end

function M.configure(s)
  if type(s) == 'table' then mergeInto(settings, s) end
  if not fellBack then mode = settings.routing == 'decal' and 'decal' or 'road' end
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

-- ---- the materials' sizes
local function loadSizes()
  sizes = {}
  local ok, markMaterials = pcall(require, 'carSurfaceFx/markMaterials')
  if not ok then return end
  for _, t in ipairs(markMaterials.index()) do
    local kind = tostring(t.type):match('^rut_(%a+)$')
    if kind then sizes[kind] = { width = t.width or 0.9, length = t.textureLength or 4 } end
    local gk = tostring(t.type):match('^gouge_(%a+)$')
    if gk then sizes['gouge_' .. gk] = { width = t.width or 0.45, length = t.textureLength or 3 } end
  end
end
local function colorFor(kind, layer)
  local key = kind .. layer
  local c = colorCache[key]
  if not c then
    local base = COLORS[kind] or COLORS.dirt
    c = ColorF(base[1], base[2], base[3], 0.35 + 0.15 * layer)
    colorCache[key] = c
  end
  return c
end
local function sizeOf(kind) return sizes[kind] or { width = 0.9, length = 4 } end

local function wetness()
  local api = rawget(_G, 'carSurfaceFx')
  local w = api and api.wetness and api.wetness()
  return tonumber(w) or 0
end

-- ---- making a chunk
local function useFallback(why)
  if fellBack then return end
  fellBack = true
  mode = 'decal'
  log('W', TAG, 'ruts: a DecalRoad could not be made (' .. tostring(why) .. '); drawing ruts as ground decals instead')
end

local function dropRoad(slot)
  local id = roads[slot]
  if id then
    local o = scenetree and scenetree.findObjectById(id)
    if o then pcall(function() o:deleteObject() end) end
    roads[slot] = nil
  end
end

local function makeRoad(chunk, material, width, layer)
  local markMaterials = require('carSurfaceFx/markMaterials')
  local okM, why = markMaterials.ensure(material)
  if not okM then return false, why end
  local ok, err = pcall(function()
    local r = createObject('DecalRoad')
    if not r then error('createObject gave nothing') end
    r:setField('improvedSpline', 0, 'true')
    r:setField('material', 0, material)
    r:setField('overObjects', 0, 'true')
    r:setField('renderPriority', 0, 10 + layer)
    r:setField('textureLength', 0, tostring(sizeOf(chunk.kind).length))
    r:registerObject('')
    if scenetree and scenetree.MissionGroup then scenetree.MissionGroup:add(r) end
    for i, p in ipairs(chunk.points) do r:insertNode(vec3(p[1], p[2], p[3] + 0.02), width, i - 1) end
    local maxN = math.max(8, math.floor(settings.maxRoads))
    roadHead = (roadHead % maxN) + 1
    dropRoad(roadHead)
    roads[roadHead] = r:getID()
    if roadN < maxN then roadN = roadN + 1 end
  end)
  if not ok then return false, err end
  made.roads = made.roads + 1
  return true
end

local function makeSegments(chunk, width, layer)
  local maxN = 600
  for i = 2, #chunk.points do
    local a, b = chunk.points[i - 1], chunk.points[i]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 1e-3 then
      segHead = (segHead % maxN) + 1
      local s = segs[segHead] or {}
      s.x, s.y, s.z, s.dx, s.dy, s.len, s.w, s.layer, s.kind = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2, dx / len, dy / len, len * 1.25, width, layer, chunk.kind
      segs[segHead] = s
      if segN < maxN then segN = segN + 1 end
      made.segments = made.segments + 1
    end
  end
end

local function makeGouge(chunk)
  local material
  material, wasWet = rules.gougeMaterial(chunk.kind, wetness(), wasWet, settings)
  local sz = sizeOf('gouge_' .. chunk.kind)
  local ok, why = makeRoad({ points = chunk.points, kind = 'gouge_' .. chunk.kind }, material, chunk.width or sz.width, 5)
  if not ok then useFallback(why) end                               -- no decal fallback for gouges: they simply stop (the ruts fall back on their own)
end

local function makeChunk(chunk)
  if chunk.gouge then makeGouge(chunk) return end
  local layer = rules.layerFor(grid, chunk.kind, chunk.points, settings)
  if layer > settings.maxLayers then made.skipped = made.skipped + 1 return end            -- the track is as deep as it gets
  local material
  material, wasWet = rules.material(chunk.kind, wetness(), wasWet, settings)
  local width = rules.width(sizeOf(chunk.kind).width, chunk.depth or 0.6, layer, settings)
  local done = false
  if mode == 'road' then
    local ok, why = makeRoad(chunk, material, width, layer)
    if ok then done = true else useFallback(why) end
  end
  if not done then makeSegments(chunk, width, layer) end
  if done and settings.berms.enabled then berm.add(settings.berms, chunk, width, chunk.depth or 0.6, layer) end
  rules.markPassed(grid, chunk.kind, chunk.points)
end

-- ---- the cars' samples
function M.sample(vid, wheel, x, y, z, kind, load, slip)
  if not settings.enabled then return end
  local depth = rules.depth(kind, load, slip, settings)
  local key = vid .. ':' .. wheel
  local path = paths[key]
  if not path then path = rules.newPath() paths[key] = path end
  path.at = os.clock()
  if depth < settings.minDepth then
    local chunk = rules.flush(path)
    if chunk and pendingN < 40 then chunk.depth = path.depth or depth pendingN = pendingN + 1 pending[pendingN] = chunk end
    return
  end
  path.depth = depth
  local chunk = rules.feed(path, x, y, z, kind, settings)
  if chunk then
    chunk.depth = depth
    if pendingN < 40 then pendingN = pendingN + 1 pending[pendingN] = chunk end
  end
end

-- a body panel dragging over the ground (from carSurfaceFx_bodywear: a 'ground' hit): the node's path becomes gouge chunks. mat = the game's material id of the ground
function M.gouge(vid, node, mat, force)
  local g = settings.gouges
  if not (settings.enabled and g.enabled) or (force or 0) < g.minForce then return end
  local kind
  pcall(function() kind = rules.gougeKind(require('carSurfaceFx/surfaces').idTable()[mat]) end)
  if not kind then return end
  local veh = be:getObjectByID(vid)
  if not veh then return end
  local ok, pos = pcall(function() return veh:getPosition() + veh:getNodePosition(node) end)
  if not ok or not pos then return end
  local key = 'g' .. vid .. ':' .. node
  local path = paths[key]
  if not path then path = rules.newPath() paths[key] = path end
  path.at, path.gouge, path.width = os.clock(), true, rules.gougeWidth(force, g)
  local chunk = rules.feed(path, pos.x, pos.y, pos.z, kind, g)
  if chunk then
    chunk.gouge, chunk.width = true, path.width
    if pendingN < 40 then pendingN = pendingN + 1 pending[pendingN] = chunk end
  end
end

function M.clear()
  for slot = 1, roadN do dropRoad(slot) end
  paths, pending, pendingN, roads, roadHead, roadN, segs, segHead, segN = {}, {}, 0, {}, 0, 0, {}, 0, 0
  grid = rules.newGrid()
  made = { roads = 0, segments = 0, skipped = 0 }
  berm.clear()
end

-- ---- drawing the fallback
function M.onPreRender(dt)
  if not settings.enabled or segN == 0 then return end
  if not (Engine and Engine.Render and Engine.Render.DynamicDecalMgr) then return end
  local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
  local camX, camY = cam and cam.x, cam and cam.y
  local cr2 = settings.cullRadius * settings.cullRadius
  local n = 0
  for i = 1, segN do
    local s = segs[i]
    if s and (not camX or (s.x - camX) ^ 2 + (s.y - camY) ^ 2 <= cr2) then
      n = n + 1
      local e = pool[n]
      if not e then
        e = { texture = RUT_TEX, position = vec3(0, 0, 0), forwardVec = vec3(1, 0, 0), color = ColorF(1, 1, 1, 1), scale = vec3(0.2, 0.2, DEPTH), fadeStart = settings.cullRadius * 0.8, fadeEnd = settings.cullRadius }
        pool[n] = e
      end
      e.position:set(s.x, s.y, s.z)
      e.forwardVec:set(s.dx, s.dy, 0)
      e.scale:set(s.w, s.len, DEPTH)
      e.color = colorFor(s.kind, s.layer)
    end
  end
  if n > 0 then
    local marks = rawget(_G, 'carSurfaceFx_marks')
    if marks and marks.drawBatch then marks.drawBatch(pool, n) else Engine.Render.DynamicDecalMgr.addDecals(pool, n) end
  end
end

function M.onUpdate(dt)
  ticks = ticks + 1
  if ticks == 1 then log('I', TAG, 'ruts: first update') end
  -- the chunks, within the budget
  while pendingN > 0 and rules.budget(bucket, 0, settings.maxPerSecond) do
    local chunk = table.remove(pending, 1)
    pendingN = pendingN - 1
    makeChunk(chunk)
  end
  rules.refill(bucket, dt, settings.maxPerSecond)                 -- (not budget: that would spend a token every frame, and the bucket would never hold one for a chunk)
  if settings.berms.enabled then berm.update(settings.berms) end
  idleT = idleT + dt
  if idleT >= 0.5 then
    idleT = 0
    local now = os.clock()
    for key, path in pairs(paths) do
      if path.at and now - path.at > 0.6 then
        local chunk = rules.flush(path)
        if chunk and pendingN < 40 then chunk.depth = path.depth or 0.6 chunk.gouge, chunk.width = path.gouge, path.width pendingN = pendingN + 1 pending[pendingN] = chunk end
        paths[key] = nil
      end
    end
  end
  injectT = injectT + dt
  if injectT >= 2 then injectT = 0 pcall(injectAll) end
  if dirty and os.clock() - lastSave > 1 then M.save() end
end

-- ---- QA
function M.mode() return mode end
function M.roadCount() return roadN end
function M.segmentCount() return segN end
function M.cells() return grid.n end
function M.pendingCount() return pendingN end

function M.status()
  return string.format('routing %s roads %d segments %d made %d/%d skipped %d cells %d pending %d wet %.2f fellBack %s ticks %d; %s', mode or '?', roadN, segN, made.roads, made.segments, made.skipped, grid.n, pendingN,
    wetness(), tostring(fellBack), ticks, berm.status())
end

-- a rut put down by hand ahead of the car: n samples along its heading on the given ground (to see how it is drawn)
function M.test(kind, passes)
  kind = kind or 'mud'
  local veh = be:getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  local p, d = veh:getPosition(), veh:getDirectionVector()
  local side = { x = -d.y, y = d.x }
  for pass = 1, passes or 1 do
    for _, off in ipairs({ -0.8, 0.8 }) do
      local path = rules.newPath()
      for i = 0, 12 do
        local x, y = p.x + d.x * (6 + i * 0.6) + side.x * off, p.y + d.y * (6 + i * 0.6) + side.y * off
        local z = p.z
        pcall(function() local h = castRayStatic(vec3(x, y, p.z + 1), vec3(0, 0, -1), 5) if h and h < 5 then z = p.z + 1 - h end end)
        local chunk = rules.feed(path, x, y, z, kind, settings)
        if chunk then chunk.depth = 1.0 pendingN = pendingN + 1 pending[pendingN] = chunk end
      end
      local last = rules.flush(path)
      if last then last.depth = 1.0 pendingN = pendingN + 1 pending[pendingN] = last end
    end
  end
  return 'rut asked: ' .. kind .. ' x' .. tostring(passes or 1)
end

-- the player's wheels count as pressing this ground wherever they are (nil to stop): a test on any ground
function M.force(kind)
  local veh = be:getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  forceKind = kind
  veh:queueLuaCommand(string.format('if carSurfaceFxRuts then carSurfaceFxRuts.force(%s) end', kind and string.format('%q', kind) or 'nil'))
  return kind and ('forcing ' .. kind) or 'forcing stopped'
end

function M.onVehicleSpawned() pcall(injectAll) end
function M.onVehicleSwitched() pcall(injectAll) end
-- carSurfaceFx.lua loads this module only while its ruts switch is on, so being loaded is being on (the module's own `enabled` defaults to false and nothing else ever set it)
function M.onExtensionLoaded() M.load() settings.enabled = true loadSizes() M.clear() pcall(injectAll) end
function M.onExtensionUnloaded()
  M.clear()
  pcall(function()
    for _, v in ipairs(getAllVehicles()) do v:queueLuaCommand('if carSurfaceFxRuts then carSurfaceFxRuts.setConfig(false, 0.6, 150) end') end
  end)
end
function M.onClientStartMission() M.clear() pcall(injectAll) end
function M.onClientEndMission() M.clear() end

M.TAG = TAG
require('carSurfaceFx/guard').wrap(M, 'carSurfaceFx_ruts', { 'onPreRender', 'onUpdate' })
return M
