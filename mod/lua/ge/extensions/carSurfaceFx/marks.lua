-- Car Surface FX: ground marks (ported from Surface FX / Enhanced Skid Marks, by the same author): skid marks and constant tyre tracks per surface, drawn as dynamic decals.
-- The car side (lua/vehicle/extensions/carSurfaceFxMarks.lua) sends one segment per wheel step; this module keeps them in ring buffers (the buffer size is how long marks last, there
-- are no timers) and draws them every frame in one batch per surface (a batch can only use one texture). Colour is multiplied over a white-on-transparent texture; every surface
-- has its own width, length, opacity, colour and texture, read from its own folder art/decals/<surface>/ (a file called track*.png is a constant-track texture).
-- Takeover: the game's own skid marks are switched off (and put back exactly when this is off) and these marks are drawn on every surface instead, hard ground included.
-- The decal draw is in drawBatch() on purpose: that is the one place to change when the decals get scene lighting.
local M = {}

local TAG = 'carSurfaceFx_marks'
local SETTINGS_FILE = 'settings/carSurfaceFx_marks.json'
local OLD_FILE = 'settings/fatkiwi_skidMarkEnhancer.json'     -- the old mod's file: read once for the values the player had set
local TRACK_TEX = 'art/decals/track.png'
local DEPTH = 1.5                                              -- how far the decal projects down: keep it big or marks vanish when a tyre digs into soft ground

M.TYPES = { 'dirt', 'sand', 'gravel', 'mud', 'grass', 'ice', 'snow', 'tarmac' }

local function matEntry(skidColor, trackColor, skidTex, trackTex, skidOpacity)
  return {
    skid = { width = 0.26, length = 1.0, opacity = skidOpacity or 0.55, color = skidColor },
    track = { width = 0.15, length = 1.0, opacity = skidOpacity and 0.4 or 0.28, color = trackColor },
    variant = skidTex, trackVariant = trackTex,
  }
end

-- the defaults, one table per module: the settings schema of the Mods menu is built from these
function M.defaults()
  return {
    enabled = true,
    takeover = true,                                             -- hide the game's own skid marks and mark every surface ourselves
    mats = {
      dirt = matEntry({ 0.20, 0.12, 0.06 }, { 0.30, 0.20, 0.11 }, 'skid_dirt_1.png', 'track_dirt_1.png', 0.8),                -- (seen in the game: the old brown was too close to the dirt itself)
      sand = matEntry({ 0.50, 0.40, 0.26 }, { 0.68, 0.58, 0.40 }, 'skid_sand_1.png', 'track_sand_1.png', 0.75),
      gravel = matEntry({ 0.28, 0.26, 0.24 }, { 0.42, 0.40, 0.37 }, 'skid_gravel_1.png', 'track_gravel_1.png', 0.75),
      mud = matEntry({ 0.20, 0.14, 0.09 }, { 0.32, 0.23, 0.15 }, 'skid_mud_1.png', 'track_mud_1.png'),
      grass = matEntry({ 0.20, 0.22, 0.10 }, { 0.30, 0.34, 0.17 }, 'skid_grass_1.png', 'track_grass_1.png', 0.75),
      ice = matEntry({ 0.72, 0.80, 0.88 }, { 0.82, 0.88, 0.94 }, 'skid_ice_1.png', 'track_ice_1.png'),
      snow = matEntry({ 0.60, 0.64, 0.72 }, { 0.74, 0.78, 0.85 }, 'skid_tread.png', 'track_snow.png'),
      tarmac = matEntry({ 0.03, 0.03, 0.03 }, { 0.05, 0.05, 0.05 }, 'skid_tarmac_1.png', 'track_tarmac_1.png'),
    },
    skidCount = 2000, trackCount = 3000,                        -- ring sizes: how many marks stay before the oldest are recycled
    wheelGap = 0.12,                                             -- reach toward the tyre in metres (grows with speed by itself)
    shade = 0.5,                                                 -- how dark marks made under cover or at night get (1 = not at all)
    cullRadius = 60,                                             -- marks further than this from the camera are not drawn
    maxDrawn = 300,                                              -- at most this many decals are drawn in a frame (the nearest ones, to the step of cullRadius / 32); each costs the engine time every frame
    perfVersion = 1,                                             -- 1: the decal budget and distance below replaced the old 800 / 100 once (M.migratePerf)
    others = { enabled = true, maxCars = 6, range = 120 },       -- traffic and AI cars mark too: the nearest maxCars within range metres
  }
end

local settings = M.defaults()
local colors = {}                                                -- type -> { skid, track, skidS, trackS } (ColorF, rebuilt when a colour changes)
local variantsSkid, variantsTrack = {}, {}                       -- type -> texture file names found in its folder
local buf = {}                                                   -- 'skid' / 'track' -> { marks, head, count }
local curShade = false
local shadeT = 0
local nativeOrig = nil                                           -- ground model name -> its real skidMarks flag while the game's marks are hidden
local injectT = 0
local dirty, lastSave = false, 0

local clamp = function(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end

local function matDir(t) return 'art/decals/' .. t .. '/' end

local function mergeInto(dst, src)
  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then mergeInto(dst[k], v) elseif type(v) == type(dst[k]) then dst[k] = v end
  end
end

-- ---- textures: every .png in a surface folder; track*.png are constant-track textures, anything else is a skid texture
local function scanDir(dir)
  local out = {}
  if rawget(_G, 'FS') then
    local files = {}
    pcall(function() files = FS:findFiles('/' .. dir, '*.png', 0, true, false) or {} end)
    for _, f in ipairs(files) do
      local name = tostring(f):match('([^/\\]+)$')
      if name then out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

function M.scanVariants()
  variantsSkid, variantsTrack = {}, {}
  for _, t in ipairs(M.TYPES) do
    local skids, tracks = {}, {}
    for _, f in ipairs(scanDir(matDir(t))) do
      if f:lower():sub(1, 5) ~= 'track' then skids[#skids + 1] = f end
      tracks[#tracks + 1] = f
    end
    if #skids == 0 then skids = { 'skid_' .. t .. '_1.png' } end
    if #tracks == 0 then tracks = { 'track_' .. t .. '_1.png' } end
    variantsSkid[t], variantsTrack[t] = skids, tracks
  end
  return variantsSkid, variantsTrack
end
function M.variants() M.scanVariants() return variantsSkid, variantsTrack end

-- ---- colours: only rebuilt when a colour, an opacity or the shade changes
local REBUILD_S, MOVE_M = 0.1, 2.0
local pools = { skid = {}, track = {} }                         -- kind -> type -> the engine's decal list (slots only: the engine reads the array part)
local used = { skid = {}, track = {} }                          -- kind -> type -> how many slots are filled
local view = { t = -1, x = 0, y = 0, fx = 0, fy = 0, dirty = true, rebuilds = 0, marksAt = 0 }
local clock = os.clock
local function rebuildColors()
  colors = {}
  view.dirty = true
  local sh = settings.shade
  for _, t in ipairs(M.TYPES) do
    local m = settings.mats[t]
    local sc, tc = m.skid.color, m.track.color
    colors[t] = {
      skid = ColorF(sc[1], sc[2], sc[3], m.skid.opacity), track = ColorF(tc[1], tc[2], tc[3], m.track.opacity),
      skidS = ColorF(sc[1] * sh, sc[2] * sh, sc[3] * sh, m.skid.opacity), trackS = ColorF(tc[1] * sh, tc[2] * sh, tc[3] * sh, m.track.opacity),
    }
  end
end

-- ---- ring buffers
local function initBuffers()
  buf = {}
  for _, k in ipairs({ 'skid', 'track' }) do buf[k] = { marks = {}, head = 0, count = 0 } end
end
local function maxN(kind) return math.max(10, math.floor(kind == 'skid' and settings.skidCount or settings.trackCount)) end

-- one wheel step, a quad from a to b; typ = surface name; kind 'skid' or 'track'; inten 0..1
local forcedSurface = nil                                       -- a test: every mark is drawn as this surface (carSurfaceFx.debug('groundsurface', 'snow'))
function M.forceSurface(name) forcedSurface = name and colors[name] and name or nil return forcedSurface end

function M.addSegment(ax, ay, az, bx, by, bz, typ, isSkid, inten)
  typ = forcedSurface or typ
  if not settings.enabled or not colors[typ] then return end
  local kind = (isSkid == 1 or isSkid == true) and 'skid' or 'track'
  if kind == 'track' then                                        -- soft ground: the ruts module draws the track as a lit road decal when its tracks switch is on
    local ruts = rawget(_G, 'carSurfaceFx_ruts')
    if ruts and ruts.trackSegment and ruts.trackSegment(typ, ax, ay, az, bx, by, bz) then return end
  end
  local b, n = buf[kind], maxN(kind)
  local dx, dy = bx - ax, by - ay
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1e-4 then return end
  local ni = (b.head % n) + 1
  local s = b.marks[ni] or {}
  s.x, s.y, s.z = (ax + bx) * 0.5, (ay + by) * 0.5, (az + bz) * 0.5
  s.dx, s.dy, s.len, s.terr, s.inten, s.shad = dx / len, dy / len, len, typ, inten or 0.5, curShade
  b.marks[ni], b.head = s, ni
  if b.count < n then b.count = b.count + 1 end
end

function M.count(kind) return buf[kind] and buf[kind].count or 0 end
function M.clear() initBuffers() view.dirty = true end

-- ---- drawing
-- The decals are submitted every frame (the engine draws them for one frame), but WHICH marks are drawn and the pool entries that describe them are only rebuilt at most REBUILD_S
-- apart and when the camera has moved or a mark was added, in ONE pass over each ring (it was one pass per surface type, every frame: 8 x 5000 marks). Between rebuilds the frame just hands
-- the same filled pools to the engine. Marks behind the camera are left out.
function M.invalidate() view.dirty = true end

local function slot(pool, idx)
  local e = pool[idx]
  if not e then
    e = { texture = TRACK_TEX, position = vec3(0, 0, 0), forwardVec = vec3(1, 0, 0), color = ColorF(1, 1, 1, 1), scale = vec3(0.2, 0.2, DEPTH),
      fadeStart = settings.cullRadius * 0.82, fadeEnd = settings.cullRadius }
    pool[idx] = e
  end
  return e
end

-- the one place a batch of decals goes to the engine (all with one texture)
local function drawBatch(pool, n) Engine.Render.DynamicDecalMgr.addDecals(pool, n) end

-- the seam for the other decal modules (the leaking fluids): the same engine call, so the scene lighting changes in one place
function M.drawBatch(pool, n) return drawBatch(pool, n) end

-- the squared distance of mark m from the camera when it may be drawn (inside the cull radius, not behind the camera), else nil
local function seen(m, camX, camY, fx, fy, cr2)
  if not camX then return 0 end
  local ddx, ddy = m.x - camX, m.y - camY
  local d2 = ddx * ddx + ddy * ddy
  if d2 > cr2 then return nil end
  if fx and d2 > 64 and ddx * fx + ddy * fy < 0 then return nil end      -- behind the camera (and not right beside it)
  return d2
end

-- when more marks are in view than the budget allows, the nearest ones win: the squared distance inside which they fit (in 32 steps of the cull radius), or math.huge when all fit
local HIST = 32
local function nearLimit(camX, camY, fx, fy, cr2, budget)
  if not camX then return math.huge end
  local hist, total, step = {}, 0, math.sqrt(cr2) / HIST
  for i = 1, HIST do hist[i] = 0 end
  for _, kind in ipairs({ 'skid', 'track' }) do
    local b = buf[kind]
    for i = 1, b.count do
      local m = b.marks[i]
      local d2 = m and seen(m, camX, camY, fx, fy, cr2)
      if d2 then local k = math.min(HIST, math.floor(math.sqrt(d2) / step) + 1) hist[k] = hist[k] + 1 total = total + 1 end
    end
  end
  if total <= budget then return math.huge end
  local acc = 0
  for k = 1, HIST do
    acc = acc + hist[k]
    if acc > budget then local r = k * step return r * r end
  end
  return math.huge
end

local function rebuildKind(kind, camX, camY, fx, fy, cr2, budget, lim2)
  local b, kp, ku = buf[kind], pools[kind], used[kind]
  for t in pairs(ku) do ku[t] = 0 end
  if b.count == 0 then return budget end
  local look = {}
  for _, t in ipairs(M.TYPES) do
    local mm, cc = settings.mats[t], colors[t]
    if mm and cc then
      local tex
      if kind == 'skid' then tex = matDir(t) .. mm.variant
      else tex = (mm.trackVariant and mm.trackVariant ~= '') and (matDir(t) .. mm.trackVariant) or TRACK_TEX end
      look[t] = { tex = tex, g = mm[kind], cc = cc }
      if not kp[t] then kp[t], ku[t] = {}, 0 end
    end
  end
  local marks = b.marks
  local fadeS, fadeE = settings.cullRadius * 0.82, settings.cullRadius        -- (a changed cull radius reaches the slots already made)
  for i = 1, b.count do
    if budget <= 0 then break end
    local m = marks[i]
    local l = m and look[m.terr]
    if l then
      local d2 = seen(m, camX, camY, fx, fy, cr2)
      if d2 and d2 <= lim2 then
        local pool, idx = kp[m.terr], ku[m.terr] + 1
        ku[m.terr] = idx
        budget = budget - 1
        local e = slot(pool, idx)
        local g, cc = l.g, l.cc
        e.texture, e.fadeStart, e.fadeEnd = l.tex, fadeS, fadeE
        e.position:set(m.x, m.y, m.z)
        e.forwardVec:set(m.dx, m.dy, 0)
        e.scale:set(kind == 'skid' and g.width * (0.85 + 0.3 * m.inten) or g.width, m.len * g.length, DEPTH)
        e.color = m.shad and (kind == 'skid' and cc.skidS or cc.trackS) or (kind == 'skid' and cc.skid or cc.track)
      end
    end
  end
  return budget
end

function M.rebuilds() return view.rebuilds end

function M.onPreRender(dt)
  if not settings.enabled then return end
  if not (Engine and Engine.Render and Engine.Render.DynamicDecalMgr) then return end
  local camX, camY, fx, fy
  local cam = core_camera and core_camera.getPosition and core_camera.getPosition()        -- culled around the camera, so free-cam and replays keep their marks
  if cam then
    camX, camY = cam.x, cam.y
    local f = core_camera.getForward and core_camera.getForward()
    if f then local l = math.sqrt(f.x * f.x + f.y * f.y) if l > 0.2 then fx, fy = f.x / l, f.y / l end end      -- looking straight up or down: no behind-the-camera cull
  end
  local now = clock()
  local moved = camX and ((camX - view.x) ^ 2 + (camY - view.y) ^ 2 > MOVE_M * MOVE_M)
  local turned = fx and (fx * view.fx + fy * view.fy < 0.95)
  if view.dirty or moved or turned or (now - view.t >= REBUILD_S and view.marksAt ~= buf.skid.head + buf.track.head) then
    view.t, view.x, view.y, view.fx, view.fy, view.dirty = now, camX or 0, camY or 0, fx or 0, fy or 0, false
    view.marksAt = buf.skid.head + buf.track.head
    view.rebuilds = view.rebuilds + 1
    local cr2 = settings.cullRadius * settings.cullRadius
    local lim2 = nearLimit(camX, camY, fx, fy, cr2, settings.maxDrawn)
    local budget = rebuildKind('track', camX, camY, fx, fy, cr2, settings.maxDrawn, lim2)
    rebuildKind('skid', camX, camY, fx, fy, cr2, budget, lim2)
  end
  for _, kind in ipairs({ 'track', 'skid' }) do
    for t, p in pairs(pools[kind]) do local n = used[kind][t] if n > 0 then drawBatch(p, n) end end
  end
end

-- ---- darker marks under cover and at night (a stand-in until decals take the scene's light)
local function updateShade()
  local veh = be and be:getPlayerVehicle(0)
  if not veh then curShade = false return end
  local p = veh:getPosition()
  local blocked = false
  pcall(function() blocked = (castRayStatic(vec3(p.x, p.y, p.z + 0.5), vec3(0, 0, 1), 60) or 999) < 59 end)
  local night = false
  pcall(function()
    if core_environment and core_environment.getTimeOfDay then
      local tod = core_environment.getTimeOfDay()
      local t = tod and (tod.time or tod)
      if type(t) == 'number' then night = t < 0.23 or t > 0.77 end
    end
  end)
  curShade = blocked or night
end

-- ---- takeover: the game's own skid marks off and back. Never calls be:resetGroundModels(): that empties the level's whole ground model list.
local function applyTakeover(hide)
  pcall(function()
    local gms = core_environment and core_environment.groundModels
    if not (be and gms) then return end
    if hide and not nativeOrig then
      nativeOrig = {}
      for name, gm in pairs(gms) do nativeOrig[name] = gm.cdata.skidMarks end        -- read them all first: aliases share one cdata
      for name, gm in pairs(gms) do gm.cdata.skidMarks = false be:setGroundModel(name, gm.cdata) end
    elseif not hide and nativeOrig then
      for name, was in pairs(nativeOrig) do
        local gm = gms[name]
        if gm then gm.cdata.skidMarks = was be:setGroundModel(name, gm.cdata) end
      end
      nativeOrig = nil
    end
  end)
end
function M.takeoverActive() return nativeOrig ~= nil end

-- ---- the cars
-- the cars that mark: the player's, and the nearest others.maxCars within others.range when traffic marks too
local function markers()
  local out, pv = {}, be:getPlayerVehicleID(0)
  local pvObj = pv and be:getObjectByID(pv)
  if pv and pv >= 0 then out[pv] = true end
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
  veh:queueLuaCommand(string.format('if not carSurfaceFxMarks then extensions.load("carSurfaceFxMarks") end carSurfaceFxMarks.setConfig(%.4f, %s, %s)',
    settings.wheelGap, settings.takeover and 'true' or 'false', emit and 'true' or 'false'))
  -- the map's own ground materials (P12, carSurfaceFx/surfaces.lua): collision type id -> surface, for the ids the car does not know by name
  local okS, lit = pcall(function() return require('carSurfaceFx/surfaces').literalNow() end)
  if okS and lit and lit ~= '{}' then veh:queueLuaCommand('if carSurfaceFxMarks and carSurfaceFxMarks.setMaterials then carSurfaceFxMarks.setMaterials(' .. lit .. ') end') end
end

local function injectAll()
  local emitters = markers()
  for _, v in ipairs(getAllVehicles()) do pushConfig(v, settings.enabled and emitters[v:getID()] == true) end
end

function M.onVehicleSpawned(id, veh) if veh or getObjectByID then pcall(injectAll) end end
function M.onVehicleSwitched() pcall(injectAll) end

-- One time: the file used to be written whole, so a player who never touched the decal budget has the OLD defaults saved (800 decals, 100 m) and would never get the cheaper new ones.
-- saved is the file's table; returns true when the old budget (800) is saved and this file has not been through this step; the radius moves only if it is the old 100. A player who sets 800 / 100 again afterwards keeps it (the file then carries perfVersion 1).
function M.migratePerf(saved)
  if type(saved) ~= 'table' or (tonumber(saved.perfVersion) or 0) >= 1 then return false end
  return saved.maxDrawn == 800
end

-- ---- settings: a file of our own, filled once from the old mod's file (the values the player set there)
function M.save() pcall(jsonWriteFile, SETTINGS_FILE, settings, true) dirty = false lastSave = os.clock() end
function M.load()
  settings = M.defaults()
  local ok, saved = pcall(jsonReadFile, SETTINGS_FILE)
  if ok and type(saved) == 'table' then
    local movePerf = M.migratePerf(saved)
    mergeInto(settings, saved)
    if movePerf then settings.maxDrawn, dirty = 300, true if saved.cullRadius == 100 then settings.cullRadius = 60 end end      -- (a radius the player changed stays)
    settings.perfVersion = 1
  else
    local ok2, old = pcall(jsonReadFile, OLD_FILE)
    if ok2 and type(old) == 'table' then
      if type(old.mats) == 'table' then mergeInto(settings.mats, old.mats) end
      for _, k in ipairs({ 'skidCount', 'trackCount', 'wheelGap', 'shade', 'cullRadius' }) do
        if type(old[k]) == 'number' then settings[k] = old[k] end
      end
      if type(old.others) == 'table' and type(old.others.enabled) == 'boolean' then settings.others.enabled = old.others.enabled end
      if type(old.takeover) == 'boolean' then settings.takeover = old.takeover end
    end
  end
  settings.cullRadius = math.max(40, math.floor(settings.cullRadius))
  settings.shade = clamp(settings.shade, 0.1, 1)
  rebuildColors()
end
function M.settings() return settings end

-- a value by its path in the settings ('mats.dirt.skid.width'); the Mods menu reads and writes through these. A path that is not in the settings is refused.
local function walk(path, create)
  local t, key = settings, nil
  local parts = {}
  for part in tostring(path):gmatch('[^%.]+') do parts[#parts + 1] = part end
  for i = 1, #parts - 1 do
    t = type(t) == 'table' and t[parts[i]] or nil
    if type(t) ~= 'table' then return nil end
  end
  key = parts[#parts]
  if type(t) ~= 'table' or t[key] == nil then return nil end
  return t, key
end
function M.get(path) local t, k = walk(path) if t then return t[k] end return nil end
function M.set(path, value)
  local t, k = walk(path)
  if not t or type(value) ~= type(t[k]) then return false end
  t[k] = value
  M.configure()
  return true
end
function M.reload() M.load() M.configure() end

-- a setting changed (from the Options page or the Mods menu): take it over now
function M.configure(s)
  if type(s) == 'table' then mergeInto(settings, s) end
  settings.skidCount, settings.trackCount = math.max(10, math.floor(settings.skidCount)), math.max(10, math.floor(settings.trackCount))
  settings.cullRadius = math.max(40, math.floor(settings.cullRadius))
  settings.shade = clamp(settings.shade, 0.1, 1)
  rebuildColors()
  pools, used = { skid = {}, track = {} }, { skid = {}, track = {} } view.dirty = true                  -- pool slots carry the fade distance
  applyTakeover(settings.enabled and settings.takeover)
  dirty = true
  pcall(injectAll)
end

function M.onUpdate(dt)
  injectT = injectT + dt
  if injectT >= 2 then injectT = 0 pcall(injectAll) end              -- car scripts get dropped on a vehicle reload, and the nearest cars change
  shadeT = shadeT + dt
  if shadeT >= 0.2 then shadeT = 0 updateShade() end
  if dirty and os.clock() - lastSave > 1 then M.save() end
end

function M.onExtensionLoaded()
  M.load()
  M.scanVariants()
  initBuffers()
  applyTakeover(settings.enabled and settings.takeover)
  pcall(injectAll)
end
function M.onExtensionUnloaded() applyTakeover(false) end             -- hand the game its own marks back
function M.onClientStartMission() initBuffers() M.scanVariants() applyTakeover(settings.enabled and settings.takeover) pcall(injectAll) end
function M.onClientEndMission() initBuffers() end

M.TAG = TAG
require('carSurfaceFx/guard').wrap(M, 'carSurfaceFx_marks', { 'onPreRender', 'onUpdate' })
return M
