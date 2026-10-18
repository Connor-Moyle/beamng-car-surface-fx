-- Car Surface FX: its settings for the Mods menu (Wrench Works' slrr_settings registry, docs/MODS_MENU.md there). Every tunable of the mod is one field here, with a plain label and
-- tooltip, in tabs and groups. The values stay where the mod reads them: the main settings file <user>/settings/carSurfaceFx.json, and the marks module's own settings through its
-- get/set. Without the registry (Car Surface FX installed alone) this is never called and the mod runs on its defaults and its json files.
local M = {}

local MAIN = '/settings/carSurfaceFx.json'

M.TABS = {
  { id = 'rain', title = 'Rain & glass', description = 'Rain on the paint and the windows, and the drops you see through the windscreen.' },
  { id = 'dirt', title = 'Dirt & wear', description = 'Dirt that builds up while you drive, and the scratches and splats on the body.' },
  { id = 'weather', title = 'Weather extras', description = 'Snow, frost, bugs and road spray.' },
  { id = 'marks', title = 'Skid marks & terrain', description = 'Marks your tyres leave on the ground, surface by surface.' },
  { id = 'textures', title = 'Textures', description = 'The pictures used for the marks. Drop your own white-on-transparent 256 x 256 PNG into a surface folder under art/decals and it shows up here.' },
}

local function title(s) return (s:gsub('^%l', string.upper)) end

local function json(path) return { kind = 'json', file = MAIN, path = path } end

-- ---- the marks module's values: its get/set by path, with the defaults when it is not running
local function marksModule() return rawget(_G, 'carSurfaceFx_marks') end
local function defaultAt(path)
  local t = require('carSurfaceFx/marks').defaults()
  for part in tostring(path):gmatch('[^%.]+') do
    if type(t) ~= 'table' then return nil end
    t = t[part]
  end
  return t
end
local function marksStore(path, kind, dir)
  local function raw()
    local m = marksModule()
    local v = m and m.get and m.get(path)
    if v == nil then v = defaultAt(path) end
    return v
  end
  return { kind = 'custom',
    get = function()
      local v = raw()
      if kind == 'color' and type(v) == 'table' then return { r = v[1], g = v[2], b = v[3] } end
      if kind == 'texture' then return '/' .. dir .. tostring(v) end
      return v
    end,
    set = function(value)
      local m = marksModule()
      if not (m and m.set) then return end
      if kind == 'color' and type(value) == 'table' then value = { value.r, value.g, value.b }
      elseif kind == 'texture' then value = tostring(value):match('([^/\\]+)$') or '' end
      m.set(path, value)
    end }
end

function M.build(S, owner)
  local marks = require('carSurfaceFx/marks')
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
    F('paint_water', 'rain', 'Wet paint', 'bool', 'Drops running over the paint', 'Drops run down the doors and fenders and stream back along the body while you drive. It uses the same paint canvas as the scratches, so it needs the scratch effect switched on.', 'scratch.water'),
    F('glass', 'rain', 'Windows', 'bool', 'Water drops on the windows', 'Drops land on the glass, merge and run down; speed and braking push them around and the wipers sweep them off. Off: the glass stays clear.', 'windscreen.enabled'),
    F('glass_strength', 'rain', 'Windows', 'slider', 'Window drops amount', 'How much rain lands on the windows. 0 is none, 100% is full.', 'windscreen.intensity', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
    F('glass_size', 'rain', 'Windows', 'slider', 'Window drop size', 'How big the drops on the outside of the glass are.', 'windscreen.dropSize', { min = 1, max = 6, step = 0.25, unit = 'x', advanced = true }),
    F('overlay', 'rain', 'Driver\'s view', 'bool', 'Drops on the windscreen from the driver\'s seat', 'In the driver and onboard cameras the drops are drawn over the windscreen as small lenses, with streaks behind the running ones and clean arcs where the wipers sweep. Off: you see no drops from inside.', 'windscreen.overlay'),
    F('overlay_size', 'rain', 'Driver\'s view', 'slider', 'Drop size in the driver\'s view', 'How big the drops are when you look through the windscreen.', 'windscreen.overlaySize', { min = 1.5, max = 8, step = 0.25, unit = 'x' }),
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

  -- ---- Skid marks & terrain
  local function mk(id, group, typ, label, tooltip, path, extra)
    local f = { id = id, tab = 'marks', group = group, type = typ, label = label, tooltip = tooltip, default = defaultAt(path), store = marksStore(path, typ == 'color' and 'color' or nil), apply = 'live' }
    if typ == 'color' then local c = f.default f.default = { r = c[1], g = c[2], b = c[3] } end
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
  end
  add({
    F('marks', 'marks', 'Skid marks', 'bool', 'Marks on the ground', 'Skid marks and tyre tracks on the ground, different on every surface. Off: your tyres leave no marks.', 'marks.enabled'),
    mk('takeover', 'Skid marks', 'bool', 'Replace the game\'s own skid marks', 'Hides the game\'s black skid marks and draws these on every surface, tarmac too. Off: the game\'s marks come back.', 'takeover'),
    mk('shade', 'Skid marks', 'slider', 'Darkness in shade and at night', 'How dark marks made under cover or at night get. 100% means not darker at all.', 'shade', { min = 0.1, max = 1, step = 0.05, unit = '%', scale = 100 }),
    mk('cull', 'Skid marks', 'slider', 'Draw distance', 'Marks further than this from the camera are not drawn. A shorter distance is easier on the frame rate.', 'cullRadius', { min = 40, max = 300, step = 10, unit = 'm' }),
    mk('max_drawn', 'Skid marks', 'int', 'Most marks drawn at once', 'A limit on the marks drawn in one frame, for the frame rate.', 'maxDrawn', { min = 100, max = 3000, advanced = true }),
    mk('skid_count', 'Skid marks', 'int', 'How many skid marks stay', 'The number of skid marks kept before the oldest are recycled. More marks last longer.', 'skidCount', { min = 100, max = 8000, advanced = true }),
    mk('track_count', 'Skid marks', 'int', 'How many tracks stay', 'The number of faint tyre tracks kept before the oldest are recycled.', 'trackCount', { min = 100, max = 10000, advanced = true }),
    mk('gap', 'Skid marks', 'slider', 'Reach toward the tyre', 'How far in front of the wheel the mark starts, in metres. It grows with speed by itself.', 'wheelGap', { min = 0, max = 0.5, step = 0.01, unit = 'm', advanced = true }),
    mk('others', 'Other cars', 'bool', 'Traffic and AI cars leave marks too', 'Off: only the car you drive marks the ground.', 'others.enabled'),
    mk('others_cars', 'Other cars', 'int', 'Most other cars that mark', 'The nearest cars up to this number leave marks, for the frame rate.', 'others.maxCars', { min = 0, max = 20 }),
    mk('others_range', 'Other cars', 'slider', 'How near a car must be', 'Cars further away than this leave no marks.', 'others.range', { min = 20, max = 300, step = 10, unit = 'm' }),
  })
  add(S.each(marks.TYPES, function(t)
    local g = 'Skid marks: ' .. title(t)
    local p = 'mats.' .. t .. '.'
    return {
      mk(t .. '_skid_w', g, 'slider', 'Skid width', 'Width of a skid mark in metres.', p .. 'skid.width', { min = 0.05, max = 0.8, step = 0.01, unit = 'm' }),
      mk(t .. '_skid_o', g, 'slider', 'Skid strength', 'How strongly a skid mark shows.', p .. 'skid.opacity', { min = 0.05, max = 1, step = 0.05, unit = '%', scale = 100 }),
      mk(t .. '_skid_c', g, 'color', 'Skid colour', 'The colour of a skid mark. It is multiplied over the texture.', p .. 'skid.color'),
      mk(t .. '_skid_l', g, 'slider', 'Skid length', 'How much the mark is stretched along its length (1 is normal).', p .. 'skid.length', { min = 0.5, max = 2, step = 0.05, unit = 'x', advanced = true }),
      mk(t .. '_track_w', g, 'slider', 'Track width', 'Width of the faint tyre track you get just from driving on this surface.', p .. 'track.width', { min = 0.05, max = 0.8, step = 0.01, unit = 'm' }),
      mk(t .. '_track_o', g, 'slider', 'Track strength', 'How strongly the faint track shows. 0 is no track.', p .. 'track.opacity', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
      mk(t .. '_track_c', g, 'color', 'Track colour', 'The colour of the faint track.', p .. 'track.color'),
      mk(t .. '_track_l', g, 'slider', 'Track length', 'How much the track is stretched along its length (1 is normal).', p .. 'track.length', { min = 0.5, max = 2, step = 0.05, unit = 'x', advanced = true }),
    }
  end))

  -- ---- Textures: one tile grid per surface and kind, read from the surface's own folder
  add(S.each(marks.TYPES, function(t)
    local dir = 'art/decals/' .. t .. '/'
    return {
      { id = t .. '_skid_tex', tab = 'textures', group = title(t), type = 'texture', label = 'Skid texture', tooltip = 'The picture of a skid mark on ' .. t .. '. White on transparent works best: the colour is multiplied over it.',
        folder = '/' .. dir, exts = { 'png' }, thumbs = true, default = '/' .. dir .. (defaultAt('mats.' .. t .. '.variant') or ''), store = marksStore('mats.' .. t .. '.variant', 'texture', dir), apply = 'live' },
      { id = t .. '_track_tex', tab = 'textures', group = title(t), type = 'texture', label = 'Track texture', tooltip = 'The picture of the faint tyre track on ' .. t .. '.',
        folder = '/' .. dir, exts = { 'png' }, thumbs = true, default = '/' .. dir .. (defaultAt('mats.' .. t .. '.trackVariant') or ''), store = marksStore('mats.' .. t .. '.trackVariant', 'texture', dir), apply = 'live' },
    }
  end))

  return { mod = 'car_surface_fx', title = 'Car Surface FX', icon = 'wrench', order = 40, tabs = M.TABS, fields = fields }
end

return M
