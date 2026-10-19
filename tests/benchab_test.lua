-- carSurfaceFx/benchab.lua against a mocked mod: one feature alternates off and on, the medians are reported, the settings come back.
local settings = { fluids = { enabled = true } }
local seen = {}
carSurfaceFx = { setSetting = function(g, k, v) local old = settings[g] and settings[g][k] if old == nil then return nil end settings[g][k] = v seen[#seen + 1] = v return old end }
log = function() end
local B = dofile('mod/lua/ge/extensions/carSurfaceFx/benchab.lua')
assert(B.run('nonsense'):find('unknown feature', 1, true), 'unknown feature refused')
assert(B.run('leaks'):find('A/B bench of leaks', 1, true) and B.run('leaks') == 'already running', 'starts once')
local frames = 0
local dt = 0.02
while B.status() ~= 'idle' and frames < 40000 do
  frames = frames + 1
  B.onUpdate(settings.fluids.enabled and dt + 0.003 or dt)         -- the "on" windows cost 3 ms more per frame
end
assert(B.status() == 'idle' and settings.fluids.enabled == true, 'it ends and the settings are as they were')
assert(#seen == 7 and seen[1] == false and seen[2] == true and seen[5] == false and seen[6] == true and seen[7] == true, 'off, on, three times, then put back: ' .. #seen)
local text = B.report()
local delta = tonumber(text:match('leaks%s+[%d%.]+%s+[%d%.]+%s+%+([%d%.]+)'))
assert(delta and math.abs(delta - 3) < 0.6, 'the median delta is about 3 ms: ' .. tostring(delta) .. '\n' .. text)
print('carSurfaceFx benchab: ok')
