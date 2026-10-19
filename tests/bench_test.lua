-- carSurfaceFx/bench.lua against a mocked mod: the steps are applied one after another, each measured, and the settings come back as they were.
local settings = { windscreen = { enabled = true, overlay = true }, scratch = { enabled = true, water = true, dirtEnabled = true }, mud = { enabled = true }, weather = { snow = true, frost = true, bugs = true, spray = true } }
local seen = {}
carSurfaceFx = { setSetting = function(g, k, v) local old = settings[g] and settings[g][k] if old == nil then return nil, 'unknown' end settings[g][k] = v return old end,
                 onUpdate = function() end }
log = function() end
local B = dofile('mod/lua/ge/extensions/carSurfaceFx/bench.lua')
assert(B.run():find('benchmark started', 1, true) and B.run() == 'already running', 'starts once')
local on = {}
local frames = 0
while B.status() ~= 'idle, 10 steps measured' and frames < 20000 do
  frames = frames + 1
  B.onUpdate(0.02)
  local s = B.status()
  local name = s:match('%((.-)%)')
  if name and not on[name] then
    on[name] = true
    seen[#seen + 1] = { name = name, overlay = settings.windscreen.overlay, glass = settings.windscreen.enabled, water = settings.scratch.water, paint = settings.scratch.enabled, mud = settings.mud.enabled, snow = settings.weather.snow }
  end
  carSurfaceFx.onUpdate()
end
assert(B.status() == 'idle, 10 steps measured', 'it ends: ' .. B.status())
assert(#seen == 10, 'ten steps seen: ' .. #seen)
assert(not seen[1].glass and not seen[1].overlay and not seen[1].paint and not seen[1].water and not seen[1].mud and not seen[1].snow, 'the first step has everything off')
assert(seen[2].paint and not seen[2].water and not seen[2].glass, 'then the paint canvases')
assert(seen[3].water and not seen[3].glass, 'then the water on the paint')
assert(seen[4].glass and not seen[4].overlay, 'then the window canvases')
assert(seen[5].overlay and not seen[5].mud, 'then the overlay')
assert(seen[6].mud and not seen[6].snow, 'then dirt')
assert(seen[9].snow, 'then the weather')
assert(settings.windscreen.enabled and settings.windscreen.overlay and settings.scratch.enabled and settings.scratch.water and settings.scratch.dirtEnabled and settings.mud.enabled
  and settings.weather.snow and settings.weather.frost and settings.weather.bugs and settings.weather.spray, 'the settings are as they were')
local text = B.report()
assert(select(2, text:gsub('\n', '\n')) >= 11 and text:find('everything off', 1, true) and text:find('all on against all off', 1, true), 'the table')
assert(carSurfaceFx.onUpdate ~= nil, 'the hooks are unwrapped')
-- stop in the middle puts the settings back
B.run()
for _ = 1, 700 do B.onUpdate(0.02) end
assert(settings.windscreen.enabled == false or settings.windscreen.enabled == true)
assert(B.stop() == 'stopped, settings put back' and settings.windscreen.overlay == true and settings.scratch.water == true, 'stop restores')
print('carSurfaceFx bench: ok')
