-- Car Surface FX: leaking fluids (oil, coolant, fuel, exhaust drips) and the puddles they make, and the grip a tyre loses in them. Written for Car Surface FX; the features follow
-- Connor's Surface FX (a car with a real leak drips under the engine, a parked leaking car builds a puddle, a tyre in a puddle slides).
-- The car side (lua/vehicle/extensions/carSurfaceFxFluids.lua) reads the car's damage and fluid state (the engine's own leak rates) and sends drips here; this module keeps the
-- puddles in a ring and draws them as decals through marks.drawBatch() (the one place the decals reach the engine, where the scene lighting will go). With the grip setting on, the
-- puddles near a car are sent back to it, and each tyre scales its own friction by the puddle it stands in.
-- Rules (what leaks, how a puddle grows, the grip maths) are in fluidrules.lua, tested by tests/fluids_test.lua.
local M = {}

local rules = require('carSurfaceFx/fluidrules')

local TAG = 'carSurfaceFx_fluids'
local SETTINGS_FILE = 'settings/carSurfaceFx_fluids.json'
local DEPTH = 1.5
local TEX = 'art/decals/fluids/puddle_%d.png'
local DROP_TEX = 'art/decals/fluids/drop.png'

local settings = rules.defaults()
local store = rules.newStore(settings.maxPuddles)
local colors = {}                                                 -- kind -> ColorF (rebuilt when a colour changes)
local dropCol = {}                                                -- kind -> ColorF for the falling drops
local reports = {}                                                -- vehicle id -> what the car last said { oil, coolant, fuel, exhaust, grip, at }
local pools = {}                                                  -- 'kind:variant' -> decal slots
local dirty, lastSave = false, 0
local injectT, ageT, gripT = 0, 0, 0
local forced = {}                                                 -- debug: kinds forced to leak on the player's car
local drops, dropN = {}, 0                                       -- the drops in the air (a small list, reused slots)

local clamp = rules.clamp
local function mergeInto(dst, src)
  for k, v in pairs(src) do
    if type(v) == 'table' and type(dst[k]) == 'table' then mergeInto(dst[k], v) elseif type(v) == type(dst[k]) then dst[k] = v end
  end
end

function M.defaults() return rules.defaults() end
function M.settings() return settings end

-- ---- colours
local function rebuildColors()
  colors = {}
  for _, kind in ipairs(rules.KINDS) do
    local c = settings.kinds[kind].color
    colors[kind] = c
    if ColorF then dropCol[kind] = ColorF(c[1], c[2], c[3], 0.9) end
  end
end

-- ---- settings: a file of our own, a value by its path ('kinds.oil.size')
function M.save() pcall(jsonWriteFile, SETTINGS_FILE, settings, true) dirty = false lastSave = os.clock() end
function M.load()
  settings = rules.defaults()
  local ok, saved = pcall(jsonReadFile, SETTINGS_FILE)
  if ok and type(saved) == 'table' then mergeInto(settings, saved) end
  settings.maxPuddles = math.max(8, math.floor(settings.maxPuddles))
  settings.cullRadius = math.max(20, settings.cullRadius)
  store = rules.newStore(settings.maxPuddles)
  rebuildColors()
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

-- the cars that leak: the player's, and the nearest others.maxCars within range when traffic leaks too
local function leakers()
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
  local ex = settings.kinds.exhaust.enabled
  veh:queueLuaCommand(string.format('if not carSurfaceFxFluids then extensions.load("carSurfaceFxFluids") end carSurfaceFxFluids.setConfig(%s, %s, %s)',
    emit and 'true' or 'false', ex and 'true' or 'false', settings.gripEnabled and 'true' or 'false'))
end

local function injectAll()
  local who = leakers()
  for _, v in ipairs(getAllVehicles()) do pushConfig(v, settings.enabled and who[v:getID()] == true) end
end

function M.configure(s)
  if type(s) == 'table' then mergeInto(settings, s) end
  settings.maxPuddles = math.max(8, math.floor(settings.maxPuddles))
  if settings.maxPuddles ~= store.max then store = rules.newStore(settings.maxPuddles) end
  rebuildColors()
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

-- ---- drips from the cars (called through obj:queueGameEngineLua by the car side)
local function groundZ(x, y, z)
  local d
  pcall(function() d = castRayStatic(vec3(x, y, z + 0.6), vec3(0, 0, -1), 4) end)
  if d and d >= 0 and d < 4 then return z + 0.6 - d end
  return nil
end

-- a drip of `kind` under a car at x, y, z (the engine's height); amount 1 is a normal one; speed in m/s tells a puddle (parked) from a trail of spots (driving)
function M.addDrip(x, y, z, kind, amount, speed)
  if not settings.enabled then return end
  local gz = groundZ(x, y, z)
  if not gz then return end
  if settings.fallingDrops and settings.kinds[kind] and settings.kinds[kind].enabled and z - gz > 0.08 and dropN < settings.maxDrops then
    dropN = dropN + 1
    local d = drops[dropN] or { pos = vec3(0, 0, 0) }
    d.x, d.y, d.z, d.vz, d.gz, d.kind, d.amount, d.speed = x, y, z, 0, gz, kind, amount or 1, speed or 0
    drops[dropN] = d
    return
  end
  rules.drip(store, x, y, gz, kind, amount or 1, settings, (speed or 0) > settings.stainSpeed, math.random())
end

-- the drops in the air fall; the one that lands makes its drip. Swap-remove keeps the list packed without allocating.
local function fallDrops(dt)
  local i = 1
  while i <= dropN do
    local d = drops[i]
    if rules.fallStep(d, dt) then
      rules.drip(store, d.x, d.y, d.gz, d.kind, d.amount, settings, d.speed > settings.stainSpeed, math.random())
      drops[i], drops[dropN] = drops[dropN], d
      dropN = dropN - 1
    else
      i = i + 1
    end
  end
end

local function drawDrops()
  if dropN == 0 or not debugDrawer then return end
  for i = 1, dropN do
    local d = drops[i]
    local c = dropCol[d.kind]
    if c then
      d.pos:set(d.x, d.y, d.z)
      pcall(debugDrawer.drawSphere, debugDrawer, d.pos, settings.dropSize, c)
    end
  end
end

-- what a car says about itself, twice a second: its leak intensities and the grip multiplier its tyres are on
function M.report(vid, oil, coolant, fuel, exhaust, grip)
  local r = reports[vid] or {}
  r.oil, r.coolant, r.fuel, r.exhaust, r.grip, r.at = oil or 0, coolant or 0, fuel or 0, exhaust or 0, grip or 1, os.clock()
  reports[vid] = r
end

-- a car's five-times-a-second report (carSurfaceFxFluids on the car): what it leaks now, from its damage and the engine's own fluid rates; the drips follow
local carry, lastAt = {}, {}
function M.car(vid, speed, ex, ey, ez, tx, ty, tz, oilPan, oilCooler, radiator, overheat, oilRate, coolRate, fuelRate, fuelStored, cold, running, grip)
  if not settings.enabled then return end
  local now = os.clock()
  local dt = clamp(now - (lastAt[vid] or now - 0.2), 0.02, 0.6)
  lastAt[vid] = now
  local leak = rules.leaks({ oilPan = oilPan, oilCooler = oilCooler, radiator = radiator, overheating = overheat, oilRate = tonumber(oilRate), coolantRate = tonumber(coolRate),
    fuelRate = fuelRate, fuelStored = fuelStored, cold = cold, running = running })
  M.report(vid, leak.oil, leak.coolant, leak.fuel, leak.exhaust, grip)
  local c = carry[vid] or {}
  carry[vid] = c
  for _, kind in ipairs(rules.KINDS) do
    local n
    n, c[kind] = rules.drips(leak[kind], dt, c[kind])
    for _ = 1, n do
      local jx, jy = (math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.5
      if kind == 'exhaust' then M.addDrip(tx + jx * 0.3, ty + jy * 0.3, tz, kind, 1, speed)
      else M.addDrip(ex + jx, ey + jy, ez, kind, 1, speed) end
    end
  end
end

function M.count() return store.count end
function M.dropCount() return dropN end
function M.clear() store = rules.newStore(settings.maxPuddles) reports = {} carry, lastAt = {}, {} dropN = 0 end

-- ---- drawing: one batch per fluid and texture variant, through marks.drawBatch (the seam where the scene light goes)
local function slot(pool, i)
  local e = pool[i]
  if not e then
    e = { texture = TEX:format(1), position = vec3(0, 0, 0), forwardVec = vec3(1, 0, 0), color = ColorF(1, 1, 1, 1), scale = vec3(0.2, 0.2, DEPTH),
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

function M.onPreRender(dt)
  if not settings.enabled then return end
  drawDrops()
  if store.count == 0 then return end
  if not (Engine and Engine.Render and Engine.Render.DynamicDecalMgr) then return end
  local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
  local camX, camY = cam and cam.x, cam and cam.y
  local cr2 = settings.cullRadius * settings.cullRadius
  for _, kind in ipairs(rules.KINDS) do
    local c = colors[kind]
    for v = 1, 3 do
      local pool, n = pools[kind .. ':' .. v], 0
      if not pool then pool = {} pools[kind .. ':' .. v] = pool end
      for i = 1, store.count do
        local p = store.list[i]
        if p and p.kind == kind and (p.variant or 1) == v and p.r > 0.02 then
          local draw_ = true
          if camX then local dx, dy = p.x - camX, p.y - camY draw_ = dx * dx + dy * dy <= cr2 end
          if draw_ then
            n = n + 1
            local e = slot(pool, n)
            e.texture = p.stain and DROP_TEX or TEX:format(v)
            e.position:set(p.x, p.y, p.z)
            local ca, sa = math.cos(p.angle or 0), math.sin(p.angle or 0)
            e.forwardVec:set(ca, sa, 0)
            e.scale:set(p.r * 2, p.r * 2 * 0.85, DEPTH)
            e.color = ColorF(c[1], c[2], c[3], rules.alpha(p, settings))
          end
        end
      end
      if n > 0 then draw(pool, n) end
    end
  end
end

-- ---- grip: the puddles near each leaking car go to it as a short list (it applies them per tyre)
local function pushGrip()
  local who = leakers()
  for id in pairs(who) do
    local veh = be:getObjectByID(id)
    if veh then
      local list = {}
      if settings.gripEnabled then
        local p = veh:getPosition()
        list = rules.near(store, p.x, p.y, 14, settings, 6)
      end
      local parts = {}
      for i, e in ipairs(list) do parts[i] = string.format('{%.2f,%.2f,%.2f,%.2f,%.2f}', e[1], e[2], e[3], e[4], e[5]) end
      veh:queueLuaCommand('if carSurfaceFxFluids then carSurfaceFxFluids.setPuddles({' .. table.concat(parts, ',') .. '}) end')
    end
  end
end

-- ---- debug / QA
-- force a kind of leak on the player's car without damage (a test: the real thing is a punctured oil pan)
function M.force(kind, on)
  local veh = be:getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  forced[kind] = on and true or nil
  veh:queueLuaCommand(string.format('if carSurfaceFxFluids then carSurfaceFxFluids.force(%q, %s) end', tostring(kind), on and 'true' or 'false'))
  return (on and 'forcing ' or 'stopped forcing ') .. tostring(kind)
end

-- a real puncture of the player's engine (oil pan or radiator) through the engine's own damage call
function M.puncture(kind)
  local veh = be:getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  veh:queueLuaCommand(string.format('if not carSurfaceFxFluids then extensions.load("carSurfaceFxFluids") end carSurfaceFxFluids.puncture(%q)', tostring(kind)))
  return 'puncture asked: ' .. tostring(kind)
end

-- a puddle put down by hand in front of the player's car (grip tests)
function M.puddleAhead(kind, metres, radius)
  local veh = be:getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  local p, d = veh:getPosition(), veh:getDirectionVector()
  local x, y = p.x + d.x * (metres or 8), p.y + d.y * (metres or 8)
  local z = groundZ(x, y, p.z) or p.z
  local puddle = rules.drip(store, x, y, z, kind or 'oil', 1, settings, false, 0.5)
  if puddle then puddle.r = clamp(radius or 1.2, 0.1, settings.kinds[kind or 'oil'].size) end
  return string.format('%s puddle at %.1f, %.1f r %.2f', kind or 'oil', x, y, puddle and puddle.r or 0)
end

function M.status()
  local per, biggest = {}, {}
  for i = 1, store.count do
    local p = store.list[i]
    if p and p.r > 0.02 then
      per[p.kind] = (per[p.kind] or 0) + 1
      biggest[p.kind] = math.max(biggest[p.kind] or 0, p.r)
    end
  end
  local out = {}
  for _, k in ipairs(rules.KINDS) do out[#out + 1] = string.format('%s=%d(r%.2f)', k, per[k] or 0, biggest[k] or 0) end
  local pv = be:getPlayerVehicleID(0)
  local r = reports[pv] or {}
  return string.format('puddles %d [%s] leak oil %.2f coolant %.2f fuel %.2f exhaust %.2f grip %.2f gripOn %s', store.count, table.concat(out, ' '),
    r.oil or 0, r.coolant or 0, r.fuel or 0, r.exhaust or 0, r.grip or 1, tostring(settings.gripEnabled))
end

-- the grip multiplier the rules give at a point (a test reads this against what the tyres report)
function M.gripAt(x, y) return rules.gripAt(store, x, y, settings) end

function M.onVehicleSpawned() pcall(injectAll) end
function M.onVehicleSwitched() pcall(injectAll) end

function M.onUpdate(dt)
  injectT = injectT + dt
  if injectT >= 2 then injectT = 0 pcall(injectAll) end
  fallDrops(dt)
  ageT = ageT + dt
  if ageT >= 1 then rules.age(store, ageT, settings) ageT = 0 end
  gripT = gripT + dt
  if gripT >= 0.25 then gripT = 0 pcall(pushGrip) end
  if dirty and os.clock() - lastSave > 1 then M.save() end
end

local function stopCars()
  pcall(function()
    for _, v in ipairs(getAllVehicles()) do v:queueLuaCommand('if carSurfaceFxFluids then carSurfaceFxFluids.setConfig(false, false, false) end') end
  end)
end

function M.onExtensionLoaded() M.load() pools = {} pcall(injectAll) end
function M.onExtensionUnloaded() stopCars() end
function M.onClientStartMission() M.clear() pcall(injectAll) end
function M.onClientEndMission() M.clear() end

M.TAG = TAG
return M
