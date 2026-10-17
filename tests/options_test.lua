-- The Options page group of Car Surface FX and the mapping from the game's settings to the mod's settings table.
local O = require('carSurfaceFx/options')
local L = require('slrr/optionsLayout')

-- every control names one of our setting keys, once; every key has a control and a default
local seen, controls = {}, 0
for _, item in ipairs(O.group().items) do
  if item.setting then
    assert(not seen[item.setting], 'a key twice: ' .. item.setting)
    seen[item.setting] = true
    controls = controls + 1
    assert(item.label ~= '' and #item.tooltip > 20, 'label and tooltip: ' .. item.setting)
  end
end
for name, key in pairs(O.KEYS) do
  assert(seen[key], 'control for ' .. name)
  assert(O.DEFAULTS[name] ~= nil, 'default for ' .. name)
end
assert(controls == 10, 'ten controls')

-- the mapping
local s = { rain = { enabled = true, intensity = 1 }, windscreen = { enabled = true }, scratch = { enabled = true, water = true, markSize = 1, allVehicles = false },
  mud = { enabled = true, buildup = false, rate = 1 }, traffic = false }
O.apply(s, function() return nil end)
assert(s.rain.enabled and s.rain.intensity == 1 and not s.mud.buildup, 'nothing set: nothing changed')
local vals = { csfxRain = false, csfxRainStrength = 0.4, csfxGlass = false, csfxPaintWater = false, csfxDirt = false, csfxDirtSpeed = 2, csfxScratch = false, csfxMarkSize = 9, csfxAllCars = true }
O.apply(s, function(k) return vals[k] end)
assert(s.rain.enabled == false and s.rain.intensity == 0.4, 'rain')
assert(s.windscreen.enabled == false and s.scratch.water == false, 'glass and paint water')
assert(s.mud.enabled == false and s.mud.buildup == true and s.mud.rate == 2, 'dirt and its speed')
assert(s.scratch.enabled == false and s.scratch.markSize == 3, 'mark size is clamped')
assert(s.traffic == true and s.scratch.allVehicles == true, 'all cars')
vals.csfxDirtSpeed = 0
O.apply(s, function(k) return vals[k] end)
assert(s.mud.buildup == false, 'speed 0 means no build-up')

-- the group goes into a layout text (a small stand-in with the anchor item), next to another mod's group, and comes out again
local layout = '{"items":[{"setting":"GraphicAntialiasType","a":1},{"setting":"Other"}],"x":{"y":[]}}' .. string.rep(' ', 1100)
local one = assert(L.patchText(layout, O.MARKER, O.group(), O.ANCHOR))
assert(one:find('"_slrr":"carsurfacefx-v1"', 1, true) and one:find('csfxRain', 1, true), 'group inserted')
local two = assert(L.patchText(one, 'other-mod', { itemType = 'group', items = {} }, O.ANCHOR))
assert(two:find('csfxRain', 1, true) and two:find('other%-mod'), 'two groups side by side')
local again = assert(L.patchText(two, O.MARKER, O.group(), O.ANCHOR))
local _, n = again:gsub('carsurfacefx%-v1', '')
assert(n == 1, 'installing again replaces ours, it does not add a second')
local gone = L.strip(again, O.MARKER)
assert(not gone:find('csfxRain', 1, true) and gone:find('other%-mod'), 'ours out, the other stays')
print('carSurfaceFx options: ok')
