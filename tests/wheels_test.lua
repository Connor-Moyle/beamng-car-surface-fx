-- carSurfaceFxWheels.updateGFX (the car's wheel watcher): the water is asked about ten times a second, and the time in water still adds up.
local calls, sent = 0, {}
local wheelList = { { name = 'FL', node1 = 1, downForce = 5000, contactMaterialID1 = 3 }, { name = 'FR', node1 = 2, downForce = 5000, contactMaterialID1 = 3 },
                    { name = 'RL', node1 = 3, downForce = 5000, contactMaterialID1 = 3 }, { name = 'RR', node1 = 4, downForce = 5000, contactMaterialID1 = 3, angularVelocity = 70, radius = 0.32 } }
wheels = { wheels = wheelList }
local wet = { [1] = true, [3] = true }            -- the left wheels are in water
obj = { inWater = function(_, node) calls = calls + 1 return wet[node] == true end, getId = function() return 1 end,
        getVelocity = function() return { length = function() return 10 end } end,
        queueGameEngineLua = function(_, s) sent[#sent + 1] = s end }
electrics = { values = {} }
local M = dofile('mod/lua/vehicle/extensions/carSurfaceFxWheels.lua')
local frames, dt = 120, 1 / 60                    -- two seconds of 60 fps
for _ = 1, frames do M.updateGFX(dt) end
assert(calls <= 4 * (frames / 6 + 1), 'inWater asked about ten times a second, not every frame: ' .. calls)
assert(calls >= 4 * (frames / 8), 'but it is asked: ' .. calls)
assert(#sent >= 3, 'reports go out')
-- the share of the reported time spent in water (all, left, right) stays near the truth: any water, left wet, right dry
local last = sent[#sent]
local nums = {}
for v in last:gmatch('[%-%d%.]+') do nums[#nums + 1] = tonumber(v) end
local waterShare, waterL, waterR, spin = nums[#nums - 6], nums[#nums - 2], nums[#nums - 1], nums[#nums]
assert(waterShare and waterShare > 0.85 and waterShare <= 1.05, 'water share is about 1: ' .. tostring(waterShare))
assert(waterL > 0.85 and waterL <= 1.05 and waterR == 0, 'left wet, right dry: ' .. tostring(waterL) .. ' ' .. tostring(waterR))
assert(math.abs(spin - 22.4) < 0.1, 'the fastest tyre surface speed is reported: ' .. tostring(spin))
print('carSurfaceFx wheels: ok')
