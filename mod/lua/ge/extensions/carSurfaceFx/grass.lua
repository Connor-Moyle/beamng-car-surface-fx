-- Car Surface FX: grass that bends under the wheels (extension carSurfaceFx_grass; started by carSurfaceFx while settings.grass.enabled).
-- BeamNG 0.39 has a surface mask its ground cover shader reads (flatten, bend direction, cut) and an engine global SurfaceMaskClipmap that paints it with circle and
-- line stamps; this module stamps it from the wheels, our own way: the stamp is as wide as the tyre, as flat as the speed makes it, torn out when a wheel spins, only on
-- grass terrain, for the player's car and the cars near it. See docs/GRASS_FLATTENING.md. The rules are in carSurfaceFx/grassRules.lua (tested outside the game).
-- It owns the clipmap while it runs: the game's own wheel stamper (util_surfaceMaskWheels), if it is on, is switched off and given back on unload.
local M = {}

local rules = require('carSurfaceFx/grassRules')
local logTag = 'carSurfaceFx_grass'

local settings = rules.sanitize(nil)
local cars = {}              -- vehicle id -> { offsets = { vec3 }, axle = { m }, widths = { m }, prev = { { x, y, z } or false }, n = wheels }
local ground = {}            -- vehicle id -> { slip, loose, speed, at }: the last report of the car's wheel watcher (carSurfaceFx.onGround)
local grassIdx = {}          -- terrain material index -> is grass
local terrain
local stampLog = rules.logNew(3000)
local timer, otherTimer, checkTimer, lastPurge = 0, 0, 0, 0
local pending = {}           -- stamps to put back after a purge, drained a few every tick
local savedOther             -- was util_surfaceMaskWheels enabled when we took the clipmap over
local started, why = false, nil
local scratchPos, scratchDir, scratchUp, scratchRot, scratchWheel = vec3(), vec3(), vec3(), quat(), vec3()
local stats = { stamps = 0, circles = 0, lines = 0, skipped = 0, purges = 0, restamped = 0 }
local TICK, OTHER_EVERY = 0.05, 2        -- the player's wheels every 0.05 s (as the game's own), other cars every second tick

local function now() return (os.clockhp and os.clockhp()) or os.clock() end
local function clipmap() return rawget(_G, 'SurfaceMaskClipmap') end

-- ---- settings -------------------------------------------------------------------------------------------------------------------------------------------

function M.configure(t)
  settings = rules.sanitize(t)
  return settings
end
function M.getSettings() return settings end

-- ---- the clipmap (ours while we run) ---------------------------------------------------------------------------------------------------------------------

local function tileDir()
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or nil
  return level and ('/temp/levels/' .. level .. '/dynamicTiles') or nil
end

local function initStorage()
  local m, dir = clipmap(), tileDir()
  if m and dir then pcall(function() m:init(dir) end) end
end

-- the game's own wheel stamper would stamp the same wheels twice (and one wider): off while we run, as it was afterwards
local function takeOver()
  local u = rawget(_G, 'util_surfaceMaskWheels')
  if u and u.enabled then
    if savedOther == nil then savedOther = true end
    if u.setEnabled then u.setEnabled(false) end
  end
end

local function giveBack()
  local u = rawget(_G, 'util_surfaceMaskWheels')
  if u and savedOther and u.setEnabled then u.setEnabled(true) end
  savedOther = nil
end

-- ---- terrain ---------------------------------------------------------------------------------------------------------------------------------------------

local function terrainObj()
  if terrain then return terrain end
  terrain = core_terrain and core_terrain.getTerrain and core_terrain.getTerrain() or nil
  return terrain
end

local function isGrassAt(x, y)
  local t = terrainObj()
  if not t then return false end
  scratchPos:set(x, y, 0)
  local idx = t:getMaterialIdxWs(scratchPos)
  local g = grassIdx[idx]
  if g == nil then
    g = rules.isGrassName(t:getMaterialName(idx))
    grassIdx[idx] = g
  end
  return g
end

-- ---- the wheels of a car ---------------------------------------------------------------------------------------------------------------------------------

local function build(veh)
  local car = { offsets = {}, axle = {}, widths = {}, prev = {}, n = 0 }
  local count = (veh:getWheelCount() or 0) - 1
  if count < 0 then return car end
  scratchDir:set(veh:getDirectionVectorXYZ())
  scratchUp:set(veh:getDirectionVectorUpXYZ())
  scratchRot:setFromDir(scratchDir, scratchUp)
  local x, y, z = scratchRot * vec3(1, 0, 0), scratchRot * vec3(0, 1, 0), scratchRot * vec3(0, 0, 1)
  for i = 0, count do
    local nodes = veh:getWheelAxisNodes(i)
    if nodes and nodes[1] then
      local p = vec3(veh:getNodePosition(nodes[1]))
      car.n = car.n + 1
      car.offsets[car.n] = vec3(p:dot(x), p:dot(y), p:dot(z))
      local axle
      if nodes[2] and nodes[2] ~= nodes[1] then axle = (p - vec3(veh:getNodePosition(nodes[2]))):length() end
      car.axle[car.n] = axle
      car.widths[car.n] = rules.stampWidth(axle, 1)
      car.prev[car.n] = false
    end
  end
  return car
end

local function carOf(veh)
  local id = veh:getID()
  local car = cars[id]
  if not car or car.n == 0 then
    car = build(veh)
    cars[id] = car
  end
  return car, id
end

-- ---- stamping --------------------------------------------------------------------------------------------------------------------------------------------

local function stampLine(x1, y1, x2, y2, width, flatten, mark, t)
  local m = clipmap()
  if not m then return end
  m:maskLineWorld(x1, y1, x2, y2, width, flatten, mark)
  rules.logAdd(stampLog, t, x1, y1, x2, y2, width, flatten, mark)
  stats.stamps, stats.lines = stats.stamps + 1, stats.lines + 1
end

local function stampCircle(x, y, radius, flatten, mark, t)
  local m = clipmap()
  if not m then return end
  m:maskCircleWorld(x, y, radius, flatten, mark)
  rules.logAdd(stampLog, t, x, y, nil, nil, radius * 2, flatten, mark)
  stats.stamps, stats.circles = stats.stamps + 1, stats.circles + 1
end

-- one car's wheels this tick
local function stampCar(veh, t)
  local car, id = carOf(veh)
  if car.n == 0 then return end
  scratchPos:set(veh:getPositionXYZ())
  scratchDir:set(veh:getDirectionVectorXYZ())
  scratchUp:set(veh:getDirectionVectorUpXYZ())
  scratchRot:setFromDir(scratchDir, scratchUp)
  local vx, vy, vz = veh:getVelocityXYZ()
  local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
  local g = ground[id]
  local slip = (g and t - g.at < 1.5) and g.slip or 0
  local flatten = rules.flatten(speed, settings.strength)
  local mark = rules.mark(slip, settings.wheelspinCut)
  for i = 1, car.n do
    scratchWheel:setRotate(scratchRot, car.offsets[i])
    scratchWheel:setAdd(scratchPos)
    local px, py, pz = scratchWheel.x, scratchWheel.y, scratchWheel.z
    local prev = car.prev[i]
    if not isGrassAt(px, py) then
      car.prev[i] = false                                  -- off the grass: the next contact starts a new stroke
      stats.skipped = stats.skipped + 1
    else
      local width = car.widths[i] * settings.widthScale
      if not prev then
        stampCircle(px, py, width * 0.5, flatten, mark, t)
        car.prev[i] = { x = px, y = py, z = pz }
      else
        local what = rules.step(px - prev.x, py - prev.y, pz - prev.z)
        if what == 'jump' then
          prev.x, prev.y, prev.z = px, py, pz
        elseif what == 'stamp' then
          stampLine(prev.x, prev.y, px, py, width, flatten, mark, t)
          prev.x, prev.y, prev.z = px, py, pz
        end
      end
    end
  end
end

-- cars other than the player's, near it, a few at a time
local function stampOthers(player, t)
  if not (settings.traffic and be and be.getObjectCount) then return end
  local pid = player:getID()
  local ppx, ppy = player:getPositionXYZ()
  local d2, done = settings.distance * settings.distance, 0
  for i = 0, be:getObjectCount() - 1 do
    if done >= settings.maxCars then break end
    local o = be:getObject(i)
    if o and o:getID() ~= pid then
      local ox, oy = o:getPositionXYZ()
      local dx, dy = ox - ppx, oy - ppy
      if dx * dx + dy * dy <= d2 then
        stampCar(o, t)
        done = done + 1
      end
    end
  end
end

-- ---- clearing --------------------------------------------------------------------------------------------------------------------------------------------

function M.clear()
  local m = clipmap()
  if m then m:clear() end
  stampLog = rules.logNew(3000)
  pending = {}
  for _, car in pairs(cars) do for i = 1, car.n do car.prev[i] = false end end
  return 'grass trails cleared'
end

-- the mask cannot fade: after the lifetime the whole mask is cleared and the stamps still young are put back (a few every tick, near the player)
local function purge(player, t)
  local m = clipmap()
  if not m then return end
  lastPurge = t
  local life = settings.clearAfterMin * 60
  local px, py = player:getPositionXYZ()
  local keep = rules.logRecent(stampLog, t, life, px, py, 150, 1500)
  m:clear()
  stampLog = rules.logNew(3000)
  pending = keep
  stats.purges = stats.purges + 1
end

local function drain(t)
  local n = 0
  while #pending > 0 and n < 150 do
    local e = table.remove(pending, 1)
    if e.x2 then stampLine(e.x1, e.y1, e.x2, e.y2, e.w, e.f, e.m, e.t) else stampCircle(e.x1, e.y1, e.w * 0.5, e.f, e.m, e.t) end
    stats.restamped = stats.restamped + 1
    n = n + 1
  end
end

-- ---- hooks -----------------------------------------------------------------------------------------------------------------------------------------------

-- from the car's wheel watcher (carSurfaceFx.onGround): the share of the last half second spent slipping, on loose ground, the speed
function M.noteGround(id, loose, mud, slip, speed)
  local g = ground[id]
  if not g then g = {} ground[id] = g end
  g.slip, g.loose, g.speed, g.at = tonumber(slip) or 0, tonumber(loose) or 0, tonumber(speed) or 0, now()
end

function M.onPreRender(dtReal, dtSim)
  if not started then return end
  local m = clipmap()
  if not m then why = 'no SurfaceMaskClipmap in this game' return end
  local dt = dtSim or dtReal or 0
  timer = timer + dt
  checkTimer = checkTimer + dt
  if checkTimer >= 1 then checkTimer = 0 takeOver() end
  if timer < TICK then return end
  timer = timer % TICK
  local t = now()
  local player = be and be:getPlayerVehicle(0)
  if not player then return end
  if #pending > 0 then drain(t) end
  if settings.clearAfterMin > 0 and rules.purgeDue(stampLog, t, settings.clearAfterMin * 60, lastPurge, math.max(20, settings.clearAfterMin * 15)) then purge(player, t) end
  scratchPos:set(player:getPositionXYZ())
  m:setCenter(scratchPos.x, scratchPos.y)
  stampCar(player, t)
  otherTimer = otherTimer + 1
  if otherTimer >= OTHER_EVERY then
    otherTimer = 0
    stampOthers(player, t)
  end
end

function M.onVehicleDestroyed(id) cars[id], ground[id] = nil, nil end
function M.onVehicleResetted(id) cars[id] = nil end                        -- a reset or a part change: the wheels are read again
function M.onVehicleSpawned(id) cars[id] = nil end

function M.onClientStartMission()
  terrain, grassIdx = nil, {}
  cars, ground, pending = {}, {}, {}
  stampLog = rules.logNew(3000)
  initStorage()
  if settings.clearOnLevel and clipmap() then clipmap():clear() end
end

function M.onClientEndMission() terrain, grassIdx, cars, ground, pending = nil, {}, {}, {}, {} end

function M.start()
  if started then return true end
  local m = clipmap()
  if not m then why = 'no SurfaceMaskClipmap in this game' return false end
  started, why = true, nil
  takeOver()
  initStorage()
  lastPurge = now()
  return true
end

function M.stop()
  if not started then return end
  started = false
  giveBack()
  cars, pending = {}, {}
end

function M.onExtensionLoaded() M.start() end
function M.onExtensionUnloaded() M.stop() end

function M.status()
  local u = rawget(_G, 'util_surfaceMaskWheels')
  return string.format('grass %s%s; the game\'s wheel stamper %s; stamps %d (circles %d, lines %d), skipped %d wheels off grass, purges %d, restamped %d, log %d, pending %d',
    started and 'on' or 'off', why and (' (' .. why .. ')') or '', u and (u.enabled and 'ON (we switch it off every second)' or 'off') or 'not loaded',
    stats.stamps, stats.circles, stats.lines, stats.skipped, stats.purges, stats.restamped, stampLog.n, #pending)
end

-- for the Mods menu (the Grass tab): fields in the registry's format, stored in the carSurfaceFx settings file under `grass`
M.TAB = { id = 'grass', title = 'Grass', description = 'Grass bends under the wheels, as wide as the tyre and flatter the faster you go; a spinning wheel tears it out. It needs a map with grass ground cover.' }

function M.fields(file)
  file = file or '/settings/carSurfaceFx.json'
  local function store(key) return { kind = 'json', file = file, path = 'grass.' .. key } end
  local function onChange() local f = jsonReadFile and jsonReadFile(file) M.configure(f and f.grass) end
  local D = rules.DEFAULTS
  return {
    { id = 'grass_enabled', tab = 'grass', group = 'Grass', type = 'bool', label = 'Grass bends under the wheels', default = D.enabled, store = store('enabled'), onChange = onChange,
      tooltip = 'Turns the effect on. Off leaves the grass as the game draws it.' },
    { id = 'grass_strength', tab = 'grass', group = 'Grass', type = 'slider', label = 'How flat', min = 0, max = 1, step = 0.05, default = D.strength, store = store('strength'), onChange = onChange,
      tooltip = 'How far the grass is pressed down. At full it lies flat under the tyre.' },
    { id = 'grass_width', tab = 'grass', group = 'Grass', type = 'slider', label = 'Track width', min = 0.5, max = 2, step = 0.1, default = D.widthScale, unit = 'x', store = store('widthScale'), onChange = onChange,
      tooltip = 'The width of the flattened strip as a multiple of the tyre (about one and a half tyre widths at 1).' },
    { id = 'grass_spin', tab = 'grass', group = 'Grass', type = 'bool', label = 'Wheelspin tears the grass out', default = D.wheelspinCut, store = store('wheelspinCut'), onChange = onChange,
      tooltip = 'A spinning or skidding wheel leaves bare earth, not just flat grass.' },
    { id = 'grass_traffic', tab = 'grass', group = 'Other cars', type = 'bool', label = 'Other cars bend grass too', default = D.traffic, store = store('traffic'), onChange = onChange,
      tooltip = 'Cars near you leave tracks as well. Off: only your car does.' },
    { id = 'grass_distance', tab = 'grass', group = 'Other cars', type = 'slider', label = 'How far from you', min = 20, max = 120, step = 10, default = D.distance, unit = 'm', store = store('distance'), onChange = onChange,
      tooltip = 'Other cars further away than this leave no tracks. Shorter costs less.', advanced = true },
    { id = 'grass_clear_level', tab = 'grass', group = 'Trails', type = 'bool', label = 'Clear the trails when a level loads', default = D.clearOnLevel, store = store('clearOnLevel'), onChange = onChange,
      tooltip = 'Trails otherwise stay on the map between visits.' },
    { id = 'grass_clear_after', tab = 'grass', group = 'Trails', type = 'int', label = 'Let trails go after (minutes, 0 = never)', min = 0, max = 60, default = D.clearAfterMin, store = store('clearAfterMin'), onChange = onChange,
      tooltip = 'The grass does not grow back by itself. With a time here the trails are cleared and the recent ones put back, so the old ones disappear.' },
    { id = 'grass_clear_now', tab = 'grass', group = 'Trails', type = 'button', label = 'Clear all trails now', action = function() return M.clear() end,
      tooltip = 'Puts all the grass back up.' },
  }
end

require('carSurfaceFx/guard').wrap(M, 'carSurfaceFx_grass', { 'onPreRender' })
return M
