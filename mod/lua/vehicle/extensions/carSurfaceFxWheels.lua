-- Car Surface FX, vehicle side: what the wheels are standing on. Twice a second it sends the GE extension the average dirt weight of the ground
-- under the wheels that carry load (weights by collision-type id, pushed in by carSurfaceFx) and the speed.
local M = {}
local MIN_DOWNFORCE = 200       -- N: a wheel in the air or barely touching does not count
local RUBBER_MAT = 4            -- the tyre's own material id; the ground is the other one
local INTERVAL = 0.5

local weights = {}              -- collision type id -> dirt weight
local acc, timer = 0, 0
local grounded = 0

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
  obj:queueGameEngineLua(string.format('if carSurfaceFx then carSurfaceFx.onGround(%d, %.3f, %.2f, %.3f) end', obj:getId(), w, v:length(), timer))
  acc, timer, grounded = 0, 0, 0
end

return M
