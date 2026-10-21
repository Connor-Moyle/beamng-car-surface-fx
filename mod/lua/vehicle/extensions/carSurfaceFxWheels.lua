-- Car Surface FX, vehicle side: what the wheels are doing. Twice a second it sends the GE extension, as shares of that time: wheels loaded on loose ground
-- (weighted), on mud, on road, skidding, and with a wheel in water; plus the speed, the engine temperature and the wipers (0..1, the highest electrics value whose name contains 'wiper').
-- The ground classes are collision-type ids pushed in by carSurfaceFx (setClasses).
local M = {}
local MIN_DOWNFORCE = 200       -- N: a wheel in the air or barely touching does not count
local RUBBER_MAT = 4            -- the tyre's own material id; the ground is the other one
local SKID = 5                  -- m/s of slip (scaled by load) that counts as skidding
local INTERVAL = 0.5

local loose, mud, road, snow = {}, {}, {}, {}      -- collision type id -> weight
local timer = 0
local sLoose, sMud, sRoad, tSlip, tWater, tWaterL, tWaterR = 0, 0, 0, 0, 0, 0, 0    -- time-weighted sums over the interval
local sSnow = 0
local wiperKeys, wiperScan = {}, 0
local tSpin = 0                         -- the fastest tyre surface speed (m/s) of a loaded wheel in the interval

function M.setClasses(l, m, r, s)
  loose, mud, road, snow = type(l) == 'table' and l or {}, type(m) == 'table' and m or {}, type(r) == 'table' and r or {}, type(s) == 'table' and s or {}
end

local function wipers(dt)
  wiperScan = wiperScan - dt
  if wiperScan <= 0 then                                -- the key name differs between cars: look again every 5 s
    wiperScan = 5
    wiperKeys = {}
    for k in pairs(electrics.values) do if tostring(k):lower():find('wiper', 1, true) then wiperKeys[#wiperKeys + 1] = k end end
  end
  if #wiperKeys == 0 then return -1 end                 -- this car has no wiper value: the game side decides by the rain
  local w = 0
  for _, k in ipairs(wiperKeys) do
    local v = tonumber(electrics.values[k]) or 0
    if v > w then w = v end
  end
  return math.min(w, 1)
end

-- the engine's coolant temperature in C (frost clears with it), 'nil' when the car has no such value
local function engineTemp()
  local t = tonumber(electrics.values.watertemp) or tonumber(electrics.values.oiltemp)
  return t and string.format('%.1f', t) or 'nil'
end

local waterT = 0      -- time since the wheels were last asked about water

function M.updateGFX(dt)
  local n, l, m, r, sn, skid, water, wl, wr = 0, 0, 0, 0, 0, false, false, false, false
  waterT = waterT + dt
  local askWater = waterT >= 0.1 or timer + dt >= INTERVAL       -- (obj:inWater is a call into the engine for every wheel: ten times a second is plenty for a puddle or a ford; also on the frame a report goes out, so that no time is carried over into the next one)
  for _, wd in pairs(wheels.wheels) do
    if askWater and wd.node1 and obj:inWater(wd.node1) then
      water = true
      local side = tostring(wd.name or ''):upper()                 -- FL FR RL RR: which side of the car the wheel is on
      if side:find('L', 1, true) then wl = true elseif side:find('R', 1, true) then wr = true else wl, wr = true, true end
    end
    if (wd.downForce or 0) >= MIN_DOWNFORCE then
      local id = wd.contactMaterialID1 or -1
      if id == RUBBER_MAT then id = wd.contactMaterialID2 or -1 end
      l, m, r, sn = l + (loose[id] or 0), m + (mud[id] or 0), r + (road[id] or 0), sn + (snow[id] or 0)
      n = n + 1
      tSpin = math.max(tSpin, math.abs(tonumber(wd.angularVelocity) or 0) * (tonumber(wd.radius) or 0.3))
      if math.abs(wd.lastSlip or 0) * math.min((wd.downForce or 0) * 0.1, 1) >= SKID then skid = true end
    end
  end
  if n > 0 then
    sLoose, sMud, sRoad, sSnow = sLoose + l / n * dt, sMud + m / n * dt, sRoad + r / n * dt, sSnow + sn / n * dt
    if skid then tSlip = tSlip + dt end
  end
  if askWater then       -- (what was found stands for the time since the last look)
    if water then tWater = tWater + waterT end
    if wl then tWaterL = tWaterL + waterT end
    if wr then tWaterR = tWaterR + waterT end
    waterT = 0
  end
  timer = timer + dt
  if timer < INTERVAL then return end
  local v = obj:getVelocity()
  obj:queueGameEngineLua(string.format('if carSurfaceFx then carSurfaceFx.onGround(%d, %.3f, %.3f, %.3f, %.3f, %.3f, %.2f, %.3f, %.2f, %s, %.3f, %.3f, %.2f, %.3f) end', obj:getId(),
    sLoose / timer, sMud / timer, sRoad / timer, tSlip / timer, tWater / timer, v:length(), timer, wipers(timer), engineTemp(), tWaterL / timer, tWaterR / timer, tSpin, sSnow / timer))
  timer, sLoose, sMud, sRoad, tSlip, tWater, tWaterL, tWaterR, tSpin, sSnow = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
end

return M
