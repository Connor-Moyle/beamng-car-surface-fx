-- Car Surface FX: its settings for the Mods menu (Wrench Works' slrr_settings registry, docs/MODS_MENU.md there). Every tunable of the mod is one field here, with a plain label and
-- tooltip, in tabs and groups. The values stay where the mod reads them: the main settings file <user>/settings/carSurfaceFx.json, and the marks module's own settings through its
-- get/set. Without the registry (Car Surface FX installed alone) this is never called and the mod runs on its defaults and its json files.
local M = {}

local MAIN = '/settings/carSurfaceFx.json'

M.TABS = {
  { id = 'rain', title = 'Rain & glass', description = 'Rain on the paint and the windows, and the drops you see through the windscreen.' },
  { id = 'dirt', title = 'Dirt & wear', description = 'Dirt that builds up while you drive, and the scratches and splats on the body.' },
  { id = 'weather', title = 'Weather extras', description = 'Snow, frost, bugs and road spray.' },
}

local function json(path) return { kind = 'json', file = MAIN, path = path } end

function M.build(S, owner)
  local D = owner.defaults()
  local function d(path)
    local t = D
    for part in path:gmatch('[^%.]+') do t = t[part] end
    return t
  end
  local reload = function() owner.reloadSettings() end
  -- a main-file field: id, tab, group, type, label, tooltip and the json path (its default is read from the mod's own defaults)
  local function F(id, tab, group, typ, label, tooltip, path, extra)
    local f = { id = id, tab = tab, group = group, type = typ, label = label, tooltip = tooltip, default = d(path), store = json(path), apply = 'live', onChange = reload }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
  end
  local function B(id, tab, group, label, tooltip, action) return { id = id, tab = tab, group = group, type = 'button', label = label, tooltip = tooltip, action = action } end

  local fields = {}
  local function add(list) for _, f in ipairs(list) do fields[#fields + 1] = f end end

  -- ---- Rain & glass
  add({
    F('rain', 'rain', 'Wet paint', 'bool', 'Wet paint and water beads', 'In the rain the paint gets darker and glossier and fine water beads form on it. Off: the paint stays dry in the rain.', 'rain.enabled'),
    F('rain_strength', 'rain', 'Wet paint', 'slider', 'Rain effect strength', 'How strongly the rain shows on the paint. 0 is no effect, 100% is full.', 'rain.intensity', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
    F('paint_water', 'rain', 'Wet paint', 'bool', 'Drops running over the paint', 'Drops run down the doors and fenders and stream back along the body while you drive. It needs "Scratches and wheel-arch dirt splats" switched on in Dirt & wear.', 'scratch.water'),
    F('glass', 'rain', 'Windows', 'bool', 'Water drops on the windows', 'Drops land on the glass, merge and run down; speed and braking push them around and the wipers sweep them off. Off: the glass stays clear.', 'windscreen.enabled'),
    F('glass_strength', 'rain', 'Windows', 'slider', 'Window drops amount', 'How much rain lands on the windows. 0 is none, 100% is full.', 'windscreen.intensity', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
    { id = 'glass_fine', tab = 'rain', group = 'Water drops', type = 'bool', label = 'Fine window canvas on your car', tooltip = 'Draws the water on the windows of your car at twice the detail, so the drops are smaller and sharper. It costs frame rate. Applies to cars spawned afterwards. Other cars always use the normal detail.',
      default = false, apply = 'spawn', store = { kind = 'custom', get = function() return (owner.getSettings().windscreen.canvasSize or 512) >= 1024 end, set = function(v) owner.set('windscreen.canvasSize', v and 1024 or 512) end } },
    F('body_drop_mm', 'rain', 'Water drops', 'slider', 'Body drop size', 'How big the water drops on the paint are, in real millimetres across, the same on every car. It is a look choice, not a cost one.', 'rain.bodyDropMm', { min = 1, max = 10, step = 0.5, unit = 'mm' }),
    F('glass_drop_mm', 'rain', 'Water drops', 'slider', 'Glass drop size', 'How big the water drops on the windows are, in real millimetres across.', 'rain.glassDropMm', { min = 1, max = 10, step = 0.5, unit = 'mm' }),
    F('drop_amount', 'rain', 'Water drops', 'slider', 'Drop amount', 'How many drops there are on the paint and the windows (1 is the normal amount).', 'rain.dropAmount', { min = 0.2, max = 3, step = 0.1, unit = 'x' }),
    F('drop_impacts', 'rain', 'Water drops', 'slider', 'Raindrop impacts', 'The small ring where a raindrop lands on the paint and the glass. 0 is none.', 'rain.impacts', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
    F('overlay', 'rain', 'Driver\'s view', 'bool', 'Drops on the windscreen from the driver\'s seat', 'In the driver and onboard cameras the drops are drawn over the windscreen as small lenses, with streaks behind the running ones and clean arcs where the wipers sweep. Off: you see no drops from inside.', 'windscreen.overlay'),
    F('overlay_size', 'rain', 'Driver\'s view', 'slider', 'Drop size in the driver\'s view', 'How big the drops are when you look through the windscreen.', 'windscreen.overlayDropSize', { min = 0.5, max = 4, step = 0.1, unit = 'x' }),
  })

  -- ---- Dirt & wear
  add({
    F('dirt', 'dirt', 'Dirt', 'bool', 'Dirt on the paint', 'Dust, mud, tyre rubber and road grime tint the paint and take its gloss. Rain, water and a car wash take it off. Off: the paint stays clean.', 'mud.enabled'),
    F('dirt_build', 'dirt', 'Dirt', 'bool', 'Dirt builds up while you drive', 'Dust on dirt roads, mud when it is wet, rubber from skids, grime on tarmac. Off: dirt only appears when another mod or a command sets it.', 'mud.buildup'),
    F('dirt_speed', 'dirt', 'Dirt', 'slider', 'Dirt build-up speed', 'How fast dirt builds up (1 is the normal speed).', 'mud.rate', { min = 0.1, max = 3, step = 0.1, unit = 'x' }),
    F('dirt_strength', 'dirt', 'Dirt', 'slider', 'Dirt strength', 'How strongly the dirt shows on the paint.', 'mud.intensity', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
    B('wash', 'dirt', 'Dirt', 'Wash the car', 'Takes all the dirt off your car, as a car wash does.', function() return tostring(owner.wash()) end),
    F('scratch', 'dirt', 'Scratches', 'bool', 'Scratches and wheel-arch dirt splats', 'Hard scrapes leave scratch marks where the body touched; dirt splats build up around the wheels. Washing removes the splats, a repair removes the scratches.', 'scratch.enabled'),
    F('scratch_len', 'dirt', 'Scratches', 'slider', 'Scratch length', 'How long the scratch marks are (1 is normal).', 'scratch.markSize', { min = 0.3, max = 3, step = 0.1, unit = 'x' }),
    F('scratch_opacity', 'dirt', 'Scratches', 'slider', 'Scratch strength', 'How strongly the scratches show.', 'scratch.opacity', { min = 0.1, max = 1, step = 0.05, unit = '%', scale = 100, advanced = true }),
    { id = 'scratch_colour', tab = 'dirt', group = 'Scratches', type = 'color', label = 'Scratch colour', tooltip = 'The colour of bare metal in a scratch.', advanced = true, apply = 'live',
      default = { r = d('scratch.colour')[1], g = d('scratch.colour')[2], b = d('scratch.colour')[3] },
      store = { kind = 'custom', get = function() local c = owner.getSettings().scratch.colour return { r = c[1], g = c[2], b = c[3] } end,
        set = function(v) owner.set('scratch.colour', { v.r, v.g, v.b }) end } },
    B('repair', 'dirt', 'Scratches', 'Buff out the scratches', 'Removes the scratches of your car. The dirt stays.', function() return tostring(owner.repair()) end),
    F('splats', 'dirt', 'Wheel-arch splats', 'bool', 'Dirt splats around the wheels', 'Splats of mud and dust gather on the body around the wheel that kicks them up.', 'scratch.dirtEnabled'),
    F('splat_opacity', 'dirt', 'Wheel-arch splats', 'slider', 'Splat strength', 'How strongly the splats show.', 'scratch.dirtOpacity', { min = 0.1, max = 1, step = 0.05, unit = '%', scale = 100, advanced = true }),
    F('splat_size', 'dirt', 'Wheel-arch splats', 'slider', 'Splat size', 'Size of one splat in metres.', 'scratch.dirtSize', { min = 0.01, max = 0.15, step = 0.005, unit = 'm', advanced = true }),
    F('splat_rate', 'dirt', 'Wheel-arch splats', 'slider', 'Splat rate', 'How quickly splats gather (1 is normal).', 'scratch.dirtRate', { min = 0, max = 3, step = 0.1, unit = 'x', advanced = true }),
    F('all_cars', 'dirt', 'Other cars', 'bool', 'Apply to all cars, traffic too', 'Off: only the car you drive gets the effects. On: every car in the level does (costs more).', 'traffic'),
  })

  -- ---- Weather extras
  add({
    F('snow', 'weather', 'Snow and frost', 'bool', 'Snow on the car', 'When it snows, snow settles on the roof and hood of a car that stands, is blown off at speed and melts when it is warm.', 'weather.snow'),
    F('frost', 'weather', 'Snow and frost', 'bool', 'Frost on the windows', 'On a cold night the windows frost over; it clears as the engine warms up and in the rain.', 'weather.frost'),
    F('bugs', 'weather', 'Bugs and spray', 'bool', 'Bugs on the nose', 'Fast driving in the dry leaves small dark splats on the nose. Rain and a car wash take them off.', 'weather.bugs'),
    F('spray', 'weather', 'Bugs and spray', 'bool', 'Road spray from the car ahead', 'On a wet road a car ahead of you throws spray on your windscreen, more from trucks.', 'weather.spray'),
  })

  -- Quick setup: the values of the things that cost frames at each of the four levels (the stored values, before any display scale)
  local PRESETS = { all_cars = { false, false, false, true }, overlay_size = { 2.4, 1.6, 1.3, 1.1 }, glass_fine = { false, false, true, true } }
  local LEVELS = { 'performance', 'balanced', 'quality', 'max' }
  for _, f in ipairs(fields) do
    local list = PRESETS[f.id]
    if list then
      f.presets = {}
      for i, level in ipairs(LEVELS) do f.presets[level] = list[i] end
    end
  end

  return { mod = 'car_surface_fx', title = 'Car Surface FX', icon = 'wrench', order = 40, tabs = M.TABS, fields = fields }
end

return M
