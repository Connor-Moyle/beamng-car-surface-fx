-- Car Surface FX: its group in the game's own Options page (Graphics category) and the mapping from those settings to the mod's settings table.
-- The group is plain data in the layout's item format (copied from the field sets the Wrench Works graphics group uses); slrr/optionsLayout.lua puts it into the layout
-- file in the user folder. Each control's `setting` is an ordinary game setting (settings.getValue / setValue); the game calls onSettingsChanged when one changes.
local M = {}

M.MARKER = 'carsurfacefx-v1'
M.ANCHOR = 'GraphicAntialiasType'

M.KEYS = { rain = 'csfxRain', rainStrength = 'csfxRainStrength', glass = 'csfxGlass', paintWater = 'csfxPaintWater', dirt = 'csfxDirt', dirtSpeed = 'csfxDirtSpeed',
           scratch = 'csfxScratch', markSize = 'csfxMarkSize', allCars = 'csfxAllCars', weather = 'csfxWeather' }
M.DEFAULTS = { rain = true, rainStrength = 1, glass = true, paintWater = true, dirt = true, dirtSpeed = 1, scratch = true, markSize = 1, allCars = false, weather = true }

-- the mod's settings table from the game's settings: get(key) -> value or nil (a setting that is not there yet leaves the mod's own value alone)
function M.apply(s, get)
  local K = M.KEYS
  local function value(name) local v = get(K[name]) if v == nil then return nil end return v end
  local function flag(name) local v = value(name) if v == nil then return nil end return v == true or v == 1 or v == 'true' or v == '1' end
  local function number(name, lo, hi) local v = tonumber(value(name)) if not v then return nil end return math.max(lo, math.min(hi, v)) end
  local v
  v = flag('rain') if v ~= nil then s.rain.enabled = v end
  v = number('rainStrength', 0, 1) if v then s.rain.intensity = v end
  v = flag('glass') if v ~= nil then s.windscreen.enabled = v end
  v = flag('paintWater') if v ~= nil then s.scratch.water = v end
  v = flag('dirt') if v ~= nil then s.mud.enabled = v end
  v = number('dirtSpeed', 0, 3) if v then s.mud.buildup = v > 0 s.mud.rate = v end
  v = flag('scratch') if v ~= nil then s.scratch.enabled = v end
  v = number('markSize', 0.3, 3) if v then s.scratch.markSize = v end
  v = flag('allCars') if v ~= nil then s.traffic = v s.scratch.allVehicles = v end
  v = flag('weather') if v ~= nil then s.weather.snow, s.weather.frost, s.weather.bugs, s.weather.spray = v, v, v, v end
  return s
end

local function common(extra)
  local item = {
    version = '0.39', tooltip = '', interactive = true, condition_always_off = false, condition_not_shipping = false,
    condition_simplemenu = '', condition_visible = '', condition_enabled = '', separateLabel = true, manualApply = false, manualLua = '',
    lua = '', basic_interaction = false, slrr = true,
  }
  for k, v in pairs(extra) do item[k] = v end
  return item
end

local function checkItem(label, setting, tooltip)
  return common({ label = label, setting = setting, tooltip = tooltip, itemType = 'checkbox', component = 'OptionsCheckbox', luaOff = '',
                  valueOn = true, valueOff = false, search = { 'label', 'caption', 'tooltip', 'setting' } })
end

local function sliderItem(label, setting, tooltip, min, max, step)
  return common({ label = label, setting = setting, tooltip = tooltip, itemType = 'slider', component = 'BngSlider', min = min, max = max, step = step,
                  compact = false, valueMultiplier = 1, unit = '', search = { 'label', 'caption', 'tooltip', 'setting' } })
end

function M.group()
  local k = M.KEYS
  return common({
    interactive = false, itemType = 'group', component = 'OptionsGroup', layout = 'column', firstAsTitle = true, separateLabel = nil,
    items = {
      common({ label = 'Car Surface FX: rain, dirt and scratches', interactive = false, itemType = 'heading', component = 'OptionsHeading', icon = '_empty', variant = 'h4', search = { 'label' }, separateLabel = nil }),
      checkItem('Wet paint and water beads', k.rain, 'In the rain the paint gets darker and glossier and fine water beads form on it; they grow and merge as it rains on and fade as the car dries.'),
      sliderItem('Rain effect strength', k.rainStrength, 'How strongly the rain shows on the paint and the windows. 0 is no effect, 1 is full.', 0, 1, 0.05),
      checkItem('Water drops on the windows', k.glass, 'Drops land on the glass, merge and run down; speed and braking push them around and the wipers sweep them off.'),
      checkItem('Rain drops running over the paint', k.paintWater, 'Drops run down the doors and fenders and stream back along the body while driving. Needs the scratch effect switched on (it uses the same paint canvas).'),
      checkItem('Dirt on the paint', k.dirt, 'Dust, mud, tyre rubber and road grime tint the paint and take its gloss. Rain, water and a car wash take it off again.'),
      sliderItem('Dirt build-up speed', k.dirtSpeed, 'How fast dirt builds up while you drive (dust on dirt roads, mud when it is wet, rubber from skids, grime on tarmac). 0 means it does not build up at all; 1 is the normal speed.', 0, 3, 0.1),
      checkItem('Scratches and wheel-arch dirt splats', k.scratch, 'Hard scrapes leave scratch marks where the body touched; dirt splats build up around the wheels. Washing removes the splats, a repair removes the scratches.'),
      sliderItem('Scratch length', k.markSize, 'How long the scratch marks are (1 is normal).', 0.3, 3, 0.1),
      checkItem('Snow, frost, bugs and road spray', k.weather, 'Snow settles on the roof and hood and blows off at speed, frost forms on the glass on cold nights and clears as the engine warms up, bugs gather on the nose in fast driving, and a car ahead throws road spray on a wet road. Rain and a car wash take them off.'),
      checkItem('Apply to all cars, traffic too', k.allCars, 'Off: only the car you drive gets the effects. On: every car in the level does (costs more).'),
    },
  })
end

return M
