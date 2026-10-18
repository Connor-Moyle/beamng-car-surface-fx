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
  { id = 'crash', title = 'Glass, debris & sparks', description = 'What a crash leaves behind: glass on the road, pieces thrown off the car, and sparks where metal grinds on the ground.' },
  { id = 'ruts', title = 'Ruts', description = 'Wheel ruts in mud, snow, sand, dirt and gravel: deeper with a heavy car and soft ground, and deeper again when the same track is driven twice.' },
  { id = 'leaks', title = 'Leaks & puddles', description = 'Oil, coolant and fuel that a damaged car drips, the puddles it leaves when it stands, and how slippery they are.' },
  require('carSurfaceFx/grass').TAB,
  { id = 'textures', title = 'Textures', description = 'The pictures used for the marks. Drop your own white-on-transparent 256 x 256 PNG into a surface folder under art/decals and it shows up here.' },
}

local rules_fluid_kinds = { 'oil', 'coolant', 'fuel', 'exhaust' }
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

-- ---- the ruts module's values (carSurfaceFx_ruts)
local function rutsModule() return rawget(_G, 'carSurfaceFx_ruts') end
local function rutDefaultAt(path)
  local t = require('carSurfaceFx/rutrules').defaults()
  for part in tostring(path):gmatch('[^%.]+') do
    if type(t) ~= 'table' then return nil end
    t = t[part]
  end
  return t
end
local function rutStore(path)
  return { kind = 'custom',
    get = function()
      local m = rutsModule()
      local v = m and m.get and m.get(path)
      if v == nil then v = rutDefaultAt(path) end
      return v
    end,
    set = function(value)
      local m = rutsModule()
      if m and m.set then m.set(path, value) end
    end }
end

-- ---- the crash effects module's values (carSurfaceFx_impacts)
local function impactsModule() return rawget(_G, 'carSurfaceFx_impacts') end
local function impactDefaultAt(path)
  local t = require('carSurfaceFx/impactrules').defaults()
  for part in tostring(path):gmatch('[^%.]+') do
    if type(t) ~= 'table' then return nil end
    t = t[part]
  end
  return t
end
local function impactStore(path, kind)
  local function raw()
    local m = impactsModule()
    local v = m and m.get and m.get(path)
    if v == nil then v = impactDefaultAt(path) end
    return v
  end
  return { kind = 'custom',
    get = function()
      local v = raw()
      if kind == 'color' and type(v) == 'table' then return { r = v[1], g = v[2], b = v[3] } end
      if kind == 'texture' then return (v and v ~= '') and ('/art/decals/impacts/' .. tostring(v)) or '' end
      return v
    end,
    set = function(value)
      local m = impactsModule()
      if not (m and m.set) then return end
      if kind == 'color' and type(value) == 'table' then value = { value.r, value.g, value.b } end
      if kind == 'texture' then value = tostring(value or ''):match('([^/\\]+)$') or '' if m.rescan then m.rescan() end end
      m.set(path, value)
    end }
end

-- ---- the leaking fluids module's values (carSurfaceFx_fluids): its get/set by path, the defaults when it is not running
local function fluidsModule() return rawget(_G, 'carSurfaceFx_fluids') end
local function fluidDefaultAt(path)
  local t = require('carSurfaceFx/fluidrules').defaults()
  for part in tostring(path):gmatch('[^%.]+') do
    if type(t) ~= 'table' then return nil end
    t = t[part]
  end
  return t
end
local function fluidStore(path, kind)
  local function raw()
    local m = fluidsModule()
    local v = m and m.get and m.get(path)
    if v == nil then v = fluidDefaultAt(path) end
    return v
  end
  return { kind = 'custom',
    get = function()
      local v = raw()
      if kind == 'color' and type(v) == 'table' then return { r = v[1], g = v[2], b = v[3] } end
      if kind == 'texture' then return (v and v ~= '') and ('/art/decals/fluids/' .. tostring(v)) or '' end
      return v
    end,
    set = function(value)
      local m = fluidsModule()
      if not (m and m.set) then return end
      if kind == 'color' and type(value) == 'table' then value = { value.r, value.g, value.b } end
      if kind == 'texture' then value = tostring(value or ''):match('([^/\\]+)$') or '' if m.rescan then m.rescan() end end
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
    F('paint_water', 'rain', 'Wet paint', 'bool', 'Drops running over the paint', 'Drops run down the doors and fenders and stream back along the body while you drive. It needs "Scratches and wheel-arch dirt splats" switched on in Dirt & wear.', 'scratch.water'),
    F('glass', 'rain', 'Windows', 'bool', 'Water drops on the windows', 'Drops land on the glass, merge and run down; speed and braking push them around and the wipers sweep them off. Off: the glass stays clear.', 'windscreen.enabled'),
    F('glass_strength', 'rain', 'Windows', 'slider', 'Window drops amount', 'How much rain lands on the windows. 0 is none, 100% is full.', 'windscreen.intensity', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
    { id = 'glass_fine', tab = 'rain', group = 'Water drops', type = 'bool', label = 'Fine window canvas on your car', tooltip = 'Draws the water on the windows of your car at twice the detail, so the drops are smaller and sharper. It costs frame rate. Applies to cars spawned afterwards. Other cars always use the normal detail.',
      default = false, apply = 'spawn', store = { kind = 'custom', get = function() return (owner.getSettings().windscreen.canvasSize or 512) >= 1024 end, set = function(v) owner.set('windscreen.canvasSize', v and 1024 or 512) end } },
    F('body_drop_mm', 'rain', 'Water drops', 'slider', 'Body drop size', 'How big the water drops on the paint are, in real millimetres across, the same on every car. It is a look choice, not a cost one.', 'rain.bodyDropMm', { min = 1, max = 10, step = 0.5, unit = 'mm' }),
    F('glass_drop_mm', 'rain', 'Water drops', 'slider', 'Glass drop size', 'How big the water drops on the windows are, in real millimetres across.', 'rain.glassDropMm', { min = 1, max = 10, step = 0.5, unit = 'mm' }),
    F('drop_amount', 'rain', 'Water drops', 'slider', 'Drop amount', 'How many drops there are on the paint and the windows (1 is the normal amount).', 'rain.dropAmount', { min = 0.2, max = 3, step = 0.1, unit = 'x' }),
    F('glass_amount', 'rain', 'Water drops', 'slider', 'Glass drop amount', 'How many more drops the windows carry than the paint (on top of the drop amount). Wet glass is easy to read against the dark inside, so 3 is a good start.', 'rain.glassAmount', { min = 0.5, max = 5, step = 0.25, unit = 'x' }),
    F('drop_anim', 'rain', 'Water drops', 'slider', 'Drop animation', 'How lively the drops on the paint are: they grow in the rain, merge and run down the panels, and streak back with the wind. 0 leaves them where they are, 1 is normal, 2 is twice as fast.', 'rain.anim', { min = 0, max = 2, step = 0.1, unit = 'x' }),
    F('drop_impacts', 'rain', 'Water drops', 'slider', 'Raindrop impacts', 'The small ring where a raindrop lands on the paint and the glass. 0 is none.', 'rain.impacts', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
    F('overlay', 'rain', 'Driver\'s view', 'bool', 'Drops on the windscreen from the driver\'s seat', 'In the driver and onboard cameras the drops are drawn over the windscreen as small lenses, with streaks behind the running ones and clean arcs where the wipers sweep. Off: you see no drops from inside.', 'windscreen.overlay'),
    F('overlay_amount', 'rain', 'Driver\'s view', 'slider', 'Driver\'s view: amount of rain drops', 'How many drops cover the windscreen when you look through it. Turn it down to see the road more clearly in the rain; 0 shows none (the rain still shows on the paint and outside).', 'windscreen.overlayStrength', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
    F('overlay_size', 'rain', 'Driver\'s view', 'slider', 'Drop size in the driver\'s view', 'How big the drops are when you look through the windscreen.', 'windscreen.overlayDropSize', { min = 0.5, max = 4, step = 0.1, unit = 'x' }),
  })

  -- ---- Dirt & wear
  add({
    F('dirt', 'dirt', 'Dirt', 'bool', 'Dirt on the paint', 'Dust, mud, tyre rubber and road grime tint the paint and take its gloss. Rain, water and a car wash take it off. Off: the paint stays clean.', 'mud.enabled'),
    F('dirt_build', 'dirt', 'Dirt', 'bool', 'Dirt builds up while you drive', 'Dust on dirt roads, mud when it is wet, rubber from skids, grime on tarmac. Off: dirt only appears when another mod or a command sets it.', 'mud.buildup'),
    F('snow_speed', 'dirt', 'Dirt', 'slider', 'Snow build-up speed', 'How fast snow settles on a car that stands (1 is the normal speed: a full coat in about 3 minutes of heavy snow).', 'weather.snowRate', { min = 0.25, max = 4, step = 0.25, unit = 'x' }),
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
    F('frost_amount', 'weather', 'Snow and frost', 'slider', 'Frost: how thick it looks', 'How thick the frost looks on the windows and on the windscreen in the driver\'s view. Turn it down if frost hides the road; 0 shows none (it still forms and clears in the background).', 'weather.frostStrength', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
    F('spray', 'weather', 'Bugs and spray', 'bool', 'Road spray from the car ahead', 'On a wet road a car ahead of you throws spray on your windscreen, more from trucks.', 'weather.spray'),
    F('spray_amount', 'weather', 'Bugs and spray', 'slider', 'Road spray: how strong it looks', 'How strong the mist and spray look on the windscreen. Turn it down if the mist hides the road; 0 shows none.', 'weather.sprayStrength', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
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
    mk('cull', 'Skid marks', 'slider', 'Skid mark draw distance', 'Marks further than this from the camera are not drawn. A shorter distance is easier on the frame rate.', 'cullRadius', { min = 40, max = 300, step = 10, unit = 'm' }),
    mk('max_drawn', 'Skid marks', 'int', 'Most marks drawn at once', 'A limit on the marks drawn in one frame, for the frame rate.', 'maxDrawn', { min = 100, max = 3000, advanced = true }),
    mk('skid_count', 'Skid marks', 'int', 'How many skid marks stay', 'The number of skid marks kept before the oldest are recycled. More marks last longer.', 'skidCount', { min = 100, max = 8000, advanced = true }),
    mk('track_count', 'Skid marks', 'int', 'How many tracks stay', 'The number of faint tyre tracks kept before the oldest are recycled.', 'trackCount', { min = 100, max = 10000, advanced = true }),
    mk('gap', 'Skid marks', 'slider', 'Where a mark starts, ahead of the tyre', 'How far in front of the wheel a mark starts, in metres. It grows with speed by itself.', 'wheelGap', { min = 0, max = 0.5, step = 0.01, unit = 'm', advanced = true }),
    mk('others', 'Other cars', 'bool', 'Traffic and AI cars leave marks too', 'Off: only the car you drive marks the ground.', 'others.enabled'),
    mk('others_cars', 'Other cars', 'int', 'Most other cars that mark', 'The nearest cars up to this number leave marks, for the frame rate.', 'others.maxCars', { min = 0, max = 20 }),
    mk('others_range', 'Other cars', 'slider', 'How near a car must be', 'Cars further away than this leave no marks.', 'others.range', { min = 20, max = 300, step = 10, unit = 'm' }),
  })
  -- one surface at a time: eight surfaces of eight settings each would be sixty-four rows; a selector shows the one chosen, the most used surface first
  local SURFACES = {}
  for _, t in ipairs({ 'tarmac', 'dirt', 'gravel', 'grass', 'sand', 'mud', 'snow', 'ice' }) do
    for _, x in ipairs(marks.TYPES) do if x == t then SURFACES[#SURFACES + 1] = t end end
  end
  for _, x in ipairs(marks.TYPES) do
    local known
    for _, t in ipairs(SURFACES) do if t == x then known = true end end
    if not known then SURFACES[#SURFACES + 1] = x end
  end
  local selected = SURFACES[1]
  local surfaceOptions = {}
  for _, t in ipairs(SURFACES) do surfaceOptions[#surfaceOptions + 1] = { id = t, label = title(t) } end
  add({ { id = 'marks_surface', tab = 'marks', group = 'Surfaces', type = 'enum', label = 'Show the settings of this surface', default = SURFACES[1], apply = 'live', options = surfaceOptions,
    tooltip = 'Marks look different on every surface. Pick a surface and the settings below are the ones for it. This only changes what is shown here.',
    store = { kind = 'custom', get = function() return selected end, set = function(v) selected = v end } } })
  add(S.each(SURFACES, function(t)
    local g = 'Skid marks: ' .. title(t)
    local p = 'mats.' .. t .. '.'
    local list = {
      mk(t .. '_skid_w', g, 'slider', 'Skid width', 'Width of a skid mark in metres.', p .. 'skid.width', { min = 0.05, max = 0.8, step = 0.01, unit = 'm' }),
      mk(t .. '_skid_o', g, 'slider', 'Skid strength', 'How strongly a skid mark shows.', p .. 'skid.opacity', { min = 0.05, max = 1, step = 0.05, unit = '%', scale = 100 }),
      mk(t .. '_skid_c', g, 'color', 'Skid colour', 'The colour of a skid mark. It tints the texture picture.', p .. 'skid.color', { advanced = true }),
      mk(t .. '_skid_l', g, 'slider', 'Skid length', 'How much the mark is stretched along its length (1 is normal).', p .. 'skid.length', { min = 0.5, max = 2, step = 0.05, unit = 'x', advanced = true }),
      mk(t .. '_track_w', g, 'slider', 'Track width', 'Width of the faint tyre track you get just from driving on this surface.', p .. 'track.width', { min = 0.05, max = 0.8, step = 0.01, unit = 'm', advanced = true }),
      mk(t .. '_track_o', g, 'slider', 'Track strength', 'How strongly the faint track shows. 0 is no track.', p .. 'track.opacity', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100 }),
      mk(t .. '_track_c', g, 'color', 'Track colour', 'The colour of the faint track.', p .. 'track.color', { advanced = true }),
      mk(t .. '_track_l', g, 'slider', 'Track length', 'How much the track is stretched along its length (1 is normal).', p .. 'track.length', { min = 0.5, max = 2, step = 0.05, unit = 'x', advanced = true }),
    }
    for _, f in ipairs(list) do f.visibleIf = { field = 'marks_surface', equals = t } end
    return list
  end))

  -- ---- Leaks & puddles
  local function lk(id, group, typ, label, tooltip, path, extra)
    local f = { id = id, tab = 'leaks', group = group, type = typ, label = label, tooltip = tooltip, default = fluidDefaultAt(path), store = fluidStore(path, typ == 'color' and 'color' or nil), apply = 'live' }
    if typ == 'color' then local c = f.default f.default = { r = c[1], g = c[2], b = c[3] } end
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
  end
  add({
    F('leaks', 'leaks', 'Leaks', 'bool', 'Leaking fluids and puddles', 'A car with a damaged oil pan, radiator or fuel tank drips on the ground, and a parked leaking car makes a puddle. Off: no drips and no puddles.', 'fluids.enabled'),
    lk('leaks_grip', 'Leaks', 'bool', 'Tyres slip in puddles', 'A tyre in a puddle really loses grip (not just a look). It changes how the car drives: braking in an oil puddle spins the car.', 'gripEnabled'),
    { id = 'leaks_texture', tab = 'leaks', group = 'Pictures', type = 'texture', label = 'Puddle picture', tooltip = 'The picture of a puddle. Drop your own white-on-transparent png (name starting with puddle) into art/decals/fluids and it shows up here; none means any of them, at random.',
      folder = '/art/decals/fluids/', exts = { 'png' }, thumbs = true, none = true, default = '', store = fluidStore('texture', 'texture'), apply = 'live' },
    lk('leaks_drops', 'Leaks', 'bool', 'Drops falling from the leak', 'Small drops visibly fall from the engine to the ground before they make a spot. Off: the spots just appear.', 'fallingDrops'),
    lk('leaks_drop_size', 'Leaks', 'slider', 'Falling drop size', 'How wide the falling drops are, in metres.', 'dropSize', { min = 0.02, max = 0.2, step = 0.01, unit = 'm', advanced = true }),
    lk('leaks_drop_count', 'Leaks', 'int', 'Drops in a burst', 'How many drops fall at once from a leak, five times a second.', 'dropCount', { min = 1, max = 5, advanced = true }),
    lk('leaks_others', 'Other cars', 'bool', 'Traffic and AI cars leak too', 'Off: only the car you drive leaks.', 'others.enabled'),
    lk('leaks_others_cars', 'Other cars', 'int', 'Most other cars that leak', 'The nearest cars up to this number leak, for the frame rate.', 'others.maxCars', { min = 0, max = 12, advanced = true }),
    lk('leaks_max', 'Leaks', 'int', 'How many puddles stay', 'The number of puddles and drip spots kept before the oldest are recycled.', 'maxPuddles', { min = 8, max = 300, advanced = true }),
    lk('leaks_cull', 'Leaks', 'slider', 'Puddle draw distance', 'Puddles further than this from the camera are not drawn.', 'cullRadius', { min = 20, max = 200, step = 5, unit = 'm', advanced = true }),
    lk('leaks_stain', 'Leaks', 'slider', 'Speed above which drips make spots', 'Driving faster than this, a leak leaves a trail of drip spots on the road instead of building a puddle.', 'stainSpeed', { min = 0.5, max = 10, step = 0.5, unit = 'm/s', advanced = true }),
  })
  add(S.each(rules_fluid_kinds, function(k)
    local g = title(k)
    local p = 'kinds.' .. k .. '.'
    local list = {
      lk('leaks_' .. k .. '_on', g, 'bool', g .. ' leaks', 'Off: no ' .. k .. ' drips or puddles.', p .. 'enabled'),
      lk('leaks_' .. k .. '_color', g, 'color', g .. ' colour', 'The colour of the ' .. k .. ' on the ground. It is multiplied over the puddle picture.', p .. 'color'),
      lk('leaks_' .. k .. '_opacity', g, 'slider', g .. ' strength', 'How strongly the ' .. k .. ' shows on the ground.', p .. 'opacity', { min = 0.05, max = 1, step = 0.05, unit = '%', scale = 100 }),
      lk('leaks_' .. k .. '_size', g, 'slider', g .. ' puddle size', 'The biggest radius a ' .. k .. ' puddle grows to, in metres.', p .. 'size', { min = 0.1, max = 2.5, step = 0.05, unit = 'm' }),
      lk('leaks_' .. k .. '_growth', g, 'slider', g .. ' puddle growth', 'How fast a puddle grows under a parked car (square metres per second of a full leak).', p .. 'growth', { min = 0.001, max = 0.1, step = 0.001, advanced = true }),
      lk('leaks_' .. k .. '_life', g, 'slider', g .. ' dries after', 'Seconds until the puddle has dried. 0 means it stays until it is recycled.', p .. 'life', { min = 0, max = 3600, step = 30, unit = 's' }),
      lk('leaks_' .. k .. '_grip', g, 'slider', g .. ' grip loss', 'How much grip a tyre loses in the middle of a puddle (when tyres slip in puddles is on).', p .. 'grip', { min = 0, max = 0.9, step = 0.05, unit = '%', scale = 100 }),
    }
    return list
  end))

  -- ---- Ruts
  local function rt(id, group, typ, label, tooltip, path, extra)
    local f = { id = id, tab = 'ruts', group = group, type = typ, label = label, tooltip = tooltip, default = rutDefaultAt(path), store = rutStore(path), apply = 'live' }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
  end
  add({
    F('ruts', 'ruts', 'Ruts', 'bool', 'Wheel ruts in soft ground', 'Mud, snow, sand, dirt and gravel take a rut where a loaded wheel rolls. Off: the ground stays smooth.', 'ruts.enabled'),
    rt('ruts_routing', 'Ruts', 'enum', 'How ruts are drawn', 'Lit road decals (they take the sun, shade and wet) or plain ground decals. If the lit way cannot be made in a level, ground decals are used on their own.', 'routing',
      { options = { { id = 'road', label = 'Lit road decals' }, { id = 'decal', label = 'Ground decals' } } }),
    rt('ruts_width', 'Ruts', 'slider', 'Rut width', 'How wide the ruts are (1 is normal).', 'widthScale', { min = 0.5, max = 2, step = 0.05, unit = 'x' }),
    rt('ruts_layers', 'Ruts', 'int', 'Passes that deepen a rut', 'How many times the same track can be driven and still get deeper. 1 means a rut never deepens.', 'maxLayers', { min = 1, max = 5 }),
    rt('ruts_depth', 'Ruts', 'slider', 'How hard a wheel must press', 'The least pressing (ground softness x the wheel load) that leaves a rut. Higher means only heavy cars or soft ground rut.', 'minDepth', { min = 0.05, max = 1, step = 0.05, advanced = true }),
    rt('ruts_max', 'Ruts', 'int', 'How many rut pieces stay', 'The number of rut pieces kept before the oldest are removed.', 'maxRoads', { min = 20, max = 600, advanced = true }),
    rt('ruts_rate', 'Ruts', 'int', 'Pieces made per second', 'A limit on rut pieces made each second, for the frame rate.', 'maxPerSecond', { min = 1, max = 20, advanced = true }),
    rt('ruts_wet', 'Ruts', 'slider', 'Wet look from', 'How wet the ground must be before ruts use their wet, glossy look.', 'wetAbove', { min = 0.1, max = 0.9, step = 0.05, advanced = true }),
    rt('ruts_cull', 'Ruts', 'slider', 'Draw distance (ground decals)', 'Ground-decal ruts further than this from the camera are not drawn.', 'cullRadius', { min = 30, max = 300, step = 10, unit = 'm', advanced = true }),
    rt('ruts_others', 'Other cars', 'bool', 'Traffic and AI cars rut too', 'Off: only the car you drive leaves ruts.', 'others.enabled'),
  })
  add(S.each({ 'mud', 'snow', 'sand', 'dirt', 'gravel' }, function(k)
    local g = title(k)
    return {
      rt('ruts_' .. k .. '_on', g, 'bool', g .. ' ruts', 'Off: ' .. k .. ' stays smooth.', 'kinds.' .. k .. '.enabled'),
      rt('ruts_' .. k .. '_soft', g, 'slider', g .. ' softness', 'How easily this ground takes a rut. Higher means shallower loads rut it.', 'kinds.' .. k .. '.soft', { min = 0.1, max = 1.5, step = 0.05 }),
    }
  end))

  -- ---- Glass, debris & sparks
  local function ic(id, group, typ, label, tooltip, path, extra)
    local f = { id = id, tab = 'crash', group = group, type = typ, label = label, tooltip = tooltip, default = impactDefaultAt(path), store = impactStore(path, typ == 'color' and 'color' or nil), apply = 'live' }
    if typ == 'color' then local c = f.default f.default = { r = c[1], g = c[2], b = c[3] } end
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
  end
  add({
    F('crash', 'crash', 'Crash effects', 'bool', 'Glass, debris and sparks', 'Master switch for what a crash leaves behind. Off: no glass piles, no flying pieces, no sparks.', 'impacts.enabled'),
    ic('crash_others', 'Crash effects', 'bool', 'Traffic and AI cars too', 'Off: only the car you drive leaves glass, pieces and sparks.', 'others.enabled'),
    ic('crash_glass_on', 'Glass', 'bool', 'Glass on the road', 'A broken window leaves a pile of glass shards on the ground under it.', 'glass.enabled'),
    { id = 'crash_glass_texture', tab = 'crash', group = 'Glass', type = 'texture', label = 'Shard picture', tooltip = 'The picture of a pile of glass. Drop your own white-on-transparent png (name starting with shards) into art/decals/impacts and it shows up here; none means any of them.',
      folder = '/art/decals/impacts/', exts = { 'png' }, thumbs = true, none = true, default = '', store = impactStore('glass.texture', 'texture'), apply = 'live' },
    { id = 'crash_debris_texture', tab = 'crash', group = 'Debris', type = 'texture', label = 'Piece picture', tooltip = 'The picture of a piece of debris on the road. Drop your own white-on-transparent png (name starting with chip) into art/decals/impacts and it shows up here; none means any of them.',
      folder = '/art/decals/impacts/', exts = { 'png' }, thumbs = true, none = true, default = '', store = impactStore('debris.texture', 'texture'), apply = 'live' },
    ic('crash_glass_color', 'Glass', 'color', 'Glass colour', 'The colour of the shards. It is multiplied over the shard picture.', 'glass.color'),
    ic('crash_glass_opacity', 'Glass', 'slider', 'Glass strength', 'How strongly the shards show.', 'glass.opacity', { min = 0.1, max = 1, step = 0.05, unit = '%', scale = 100 }),
    ic('crash_glass_size', 'Glass', 'slider', 'Pile size', 'How big a pile of shards is (1 is normal).', 'glass.size', { min = 0.3, max = 3, step = 0.1, unit = 'x' }),
    ic('crash_glass_max', 'Glass', 'int', 'How many piles stay', 'The number of glass piles kept before the oldest are recycled.', 'glass.maxPiles', { min = 4, max = 200, advanced = true }),
    ic('crash_debris_on', 'Debris', 'bool', 'Pieces thrown off the car', 'A joint giving way or a hard hit throws off pieces of trim, plastic, metal or glass; they bounce, settle on the road and are cleaned up later.', 'debris.enabled'),
    ic('crash_debris_particles', 'Debris', 'bool', 'Pieces flying off as particles', 'The pieces are thrown with the particles the game itself uses (plastic chunks, flecks of metal, stones) as well as settling on the road. Off: they only appear on the road.', 'debris.particles'),
    ic('crash_debris_amount', 'Debris', 'slider', 'Amount of debris', 'How many pieces a break or a hit throws (1 is normal, 0 none).', 'debris.amount', { min = 0, max = 4, step = 0.25, unit = 'x' }),
    ic('crash_debris_size', 'Debris', 'slider', 'Piece size', 'How big the pieces are (1 is normal).', 'debris.size', { min = 0.4, max = 3, step = 0.1, unit = 'x' }),
    ic('crash_debris_life', 'Debris', 'slider', 'Pieces stay for', 'Seconds until a piece on the road is cleaned up.', 'debris.life', { min = 20, max = 1800, step = 10, unit = 's' }),
    ic('crash_debris_clear', 'Debris', 'slider', 'Cleaned up beyond', 'A piece further than this from the camera is cleaned up at once.', 'debris.clearDistance', { min = 50, max = 600, step = 10, unit = 'm', advanced = true }),
    ic('crash_debris_speed', 'Debris', 'slider', 'Hit speed that throws pieces', 'How hard a hit must be (speed into the surface, m/s) before it throws pieces.', 'debris.impactSpeed', { min = 2, max = 20, step = 0.5, unit = 'm/s', advanced = true }),
    ic('crash_debris_chance', 'Debris', 'slider', 'Chance a broken joint sheds a piece', 'How often a joint that gives way throws a piece.', 'debris.jointChance', { min = 0, max = 1, step = 0.05, unit = '%', scale = 100, advanced = true }),
    ic('crash_debris_resting', 'Debris', 'int', 'Most pieces on the road', 'The number of settled pieces kept before the oldest are recycled.', 'debris.maxResting', { min = 10, max = 500, advanced = true }),
    ic('crash_sparks_on', 'Sparks', 'bool', 'Sparks', 'Metal grinding on a hard surface throws sparks. Not on dirt, grass, snow or rubber.', 'sparks.enabled'),
    ic('crash_sparks_amount', 'Sparks', 'slider', 'Amount of sparks', 'How many sparks a scrape throws (1 is normal).', 'sparks.amount', { min = 0.25, max = 4, step = 0.25, unit = 'x' }),
    ic('crash_sparks_speed', 'Sparks', 'slider', 'Sliding speed for sparks', 'How fast the metal must slide on the surface before it throws sparks.', 'sparks.minSpeed', { min = 1, max = 15, step = 0.5, unit = 'm/s', advanced = true }),
  })

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

  add(require('carSurfaceFx/grass').fields(MAIN))

  -- Quick setup: the values of the things that cost frames at each of the four levels (the stored values, before any display scale)
  local PRESETS = {
    all_cars = { false, false, false, true }, glass_fine = { false, false, true, true }, overlay_size = { 2.4, 1.6, 1.3, 1.1 },
    cull = { 60, 100, 140, 200 }, max_drawn = { 300, 800, 1200, 2000 }, skid_count = { 800, 2000, 3000, 5000 }, track_count = { 1000, 3000, 5000, 8000 },
    others_cars = { 0, 6, 8, 12 }, others_range = { 40, 120, 150, 200 }, leaks_max = { 40, 120, 180, 300 }, leaks_cull = { 40, 80, 120, 160 },
    leaks_others_cars = { 0, 4, 6, 8 }, grass_distance = { 30, 60, 90, 120 },
  }
  local SCALED = { crash_glass_max = 1, crash_debris_flying = 1, crash_debris_resting = 1, crash_sparks_max = 1 }   -- no fixed numbers: the default times 0.4, 1, 1.5 and 2.5
  local SCALE = { 0.4, 1, 1.5, 2.5 }
  local LEVELS = { 'performance', 'balanced', 'quality', 'max' }
  for _, f in ipairs(fields) do
    local list = PRESETS[f.id]
    if not list and SCALED[f.id] and type(f.default) == 'number' then
      list = {}
      for i = 1, 4 do
        local v = f.default * SCALE[i]
        if f.type == 'int' then v = math.floor(v + 0.5) end
        list[i] = math.max(f.min or v, math.min(f.max or v, v))
      end
    end
    if list then
      f.presets = {}
      for i, level in ipairs(LEVELS) do f.presets[level] = list[i] end
    end
  end

  return { mod = 'car_surface_fx', title = 'Car Surface FX', icon = 'wrench', order = 40, tabs = M.TABS, fields = fields }
end

return M
