-- Car Surface FX, vehicle side: what the wheels are standing on. Twice a second it sends the GE extension the average dirt weight of the ground
-- under the wheels that carry load (weights by collision-type id, pushed in by carSurfaceFx), the speed and the wipers (0..1, the highest electrics value
-- whose name contains 'wiper').
local M = {}
local MIN_DOWNFORCE = 200       -- N: a wheel in the air or barely touching does not count
local RUBBER_MAT = 4            -- the tyre's own material id; the ground is the other one
local INTERVAL = 0.5

local weights = {}              -- collision type id -> dirt weight
local acc, timer = 0, 0
local grounded = 0
local wiperKeys, wiperScan = {}, 0

local function wipers(dt)
  wiperScan = wiperScan - dt
  if wiperScan <= 0 then                                -- the key name differs between cars: look again every 5 s
    wiperScan = 5
    wiperKeys = {}
    for k in pairs(electrics.values) do if tostring(k):lower():find('wiper', 1, true) then wiperKeys[#wiperKeys + 1] = k end end
  end
  local w = 0
  for _, k in ipairs(wiperKeys) do
    local v = tonumber(electrics.values[k]) or 0
    if v > w then w = v end
  end
  return math.min(w, 1)
end

function M.setWeights(t) weights = type(t) == 'table' and t or {} end

function M.updateGFX(dt)
  local sum, n = 0, 0
  for _, wd in pairs(wheels.wheels) do
    if (wd.downForce or 0) >= MIN_DOWNFORCE then
      local m = wd.contactMaterialID1 or -1
      if m == RUBBER_MAT then m = wd.contactMaterialID2 or -1 end
      sum = sum + (weights[m] or 0)
      n = n + 1
    end
  end
  if n > 0 then acc = acc + sum / n * dt grounded = grounded + dt end
  timer = timer + dt
  if timer < INTERVAL then return end
  local w = grounded > 0 and acc / grounded or 0
  local v = obj:getVelocity()
  obj:queueGameEngineLua(string.format('if carSurfaceFx then carSurfaceFx.onGround(%d, %.3f, %.2f, %.3f, %.2f) end', obj:getId(), w, v:length(), timer, wipers(timer)))
  acc, timer, grounded = 0, 0, 0
end

return M
