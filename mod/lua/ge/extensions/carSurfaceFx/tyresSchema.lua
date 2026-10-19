-- Car Surface FX: the Mods menu page "Tyres" (Wrench Works' slrr_settings registry, docs/MODS_MENU.md there). Every cfg value of the tyre rules (lua/common/csfx_tyrerules.lua, M.defaults()
-- and M.COMPOUNDS) is one field here, in tabs: Wear, Temperature, Grip, Wet, Fire & debris, Visuals, Compounds. The values live in one file, FILE, in the layout of the rules' cfg:
--   { enabled = true, wearRate = 1, surface = { asphalt = 1, ... }, flat = { ... }, debris = { ... }, blowout = { ... }, compounds = { road = { h0 = 8, ... }, ... }, preset = 'realistic' }
-- A key the file lacks is the rules' default. The game side reads that file into the cfg it hands to the vehicle side (a compound's entry overrides the same fields of M.COMPOUNDS[name]);
-- the page calls owner.reload() after a change when the owner gives one. Common values are shown, the rest are advanced (Show advanced settings).
local M = {}

M.FILE = '/settings/carSurfaceFx_tyres.json'

M.TABS = {
  { id = 'wear', title = 'Wear', description = 'The tyre simulation, its presets, and how fast tread wears away. Real tyres wear far too slowly to see in play, so the wear rate speeds time up.' },
  { id = 'temperature', title = 'Temperature', description = 'How fast tyres heat up from slip and cool down again.' },
  { id = 'grip', title = 'Grip', description = 'How temperature, pressure and tread change the grip of a tyre.' },
  { id = 'wet', title = 'Wet', description = 'Rain on tyres. Each compound\'s own wet grip is on the Compounds tab.' },
  { id = 'fire', title = 'Fire & debris', description = 'Smoking and burning tyres, rubber thrown off the tyre, and what a blowout does to the car.' },
  { id = 'visuals', title = 'Visuals', description = 'How worn tyres look.' },
  { id = 'compounds', title = 'Compounds', description = 'The tyre types one by one: the tread they start with, how fast they wear, where they grip best and how they behave in the wet.' },
}

-- the presets: cfg overrides on top of the defaults (Realistic is the defaults)
M.PRESETS = {
  realistic = {},
  arcade = { wearRate = 0.3, heatRate = 0.6, coldGrip = 0.3, hotGrip = 0.3, flat = { enabled = false }, fires = false, blowout = { enabled = false } },
  off = { enabled = false },
}

-- one row of the simple fields: tab, path, type, label, tooltip, min, max, step, unit, advanced
local function row(tab, path, typ, label, tooltip, min, max, step, unit, adv)
  return { tab = tab, path = path, type = typ, label = label, tooltip = tooltip, min = min, max = max, step = step, unit = unit, advanced = adv }
end

local ROWS = {
  row('wear', 'enabled', 'bool', 'Tyre simulation', 'Tyres wear, heat up and change their grip. Off: the game\'s own tyres, and nothing here runs.'),
  row('wear', 'wearRate', 'slider', 'Wear speed', 'How fast tyres wear compared with real life. 1 is the starting value; real wear is too slow to notice in play. 0 stops wear.', 0, 20, 0.1, 'x'),
  row('wear', 'flat.enabled', 'bool', 'Flat spots from locked wheels', 'A wheel that locks up and skids wears a flat spot into the tyre, which shakes the car.'),
  row('wear', 'surface.asphalt', 'slider', 'Wear on asphalt', 'How much a slip wears the tyre on asphalt (1 is normal).', 0, 3, 0.1, 'x', true),
  row('wear', 'surface.concrete', 'slider', 'Wear on concrete', 'Wear on concrete.', 0, 3, 0.1, 'x', true),
  row('wear', 'surface.wet', 'slider', 'Wear on a wet road', 'Wear on a wet road.', 0, 3, 0.1, 'x', true),
  row('wear', 'surface.gravel', 'slider', 'Wear on gravel', 'Wear on gravel.', 0, 3, 0.1, 'x', true),
  row('wear', 'surface.dirt', 'slider', 'Wear on dirt', 'Wear on dirt.', 0, 3, 0.1, 'x', true),
  row('wear', 'surface.rock', 'slider', 'Wear on rock', 'Wear on rock.', 0, 3, 0.1, 'x', true),
  row('wear', 'surface.snow', 'slider', 'Wear on snow', 'Wear on snow.', 0, 3, 0.1, 'x', true),
  row('wear', 'surface.ice', 'slider', 'Wear on ice', 'Wear on ice.', 0, 3, 0.1, 'x', true),
  row('wear', 'deadZone', 'slider', 'Slip that wears nothing', 'Slip slower than this (metres per second) wears no rubber: it is the tiny slip of a rolling wheel.', 0, 2, 0.05, 'm/s', true),
  row('wear', 'heatWearScale', 'slider', 'Heat that doubles wear', 'Degrees over the compound\'s wear temperature that double the wear.', 10, 200, 5, 'C', true),
  row('wear', 'heatWearMax', 'slider', 'Most extra wear from heat', 'The most the heat can multiply the wear by.', 1, 10, 0.5, 'x', true),
  row('wear', 'cordLimit', 'slider', 'Tread below zero before it fails', 'How far below zero tread the tyre goes (the belts show) before it blows.', 0, 3, 0.1, 'mm', true),
  row('wear', 'flat.minDepth', 'slider', 'Flat spot that matters', 'The depth of flat spot where it starts to shake the car and cost grip.', 0, 2, 0.05, 'mm', true),
  row('wear', 'flat.gripLoss', 'slider', 'Grip lost per flat spot', 'Grip lost for each millimetre of flat spot.', 0, 0.2, 0.005, nil, true),

  row('temperature', 'heatRate', 'slider', 'How fast tyres heat up', 'How quickly slip heats the tyre (1 is normal).', 0.1, 5, 0.1, 'x'),
  row('temperature', 'coolRate', 'slider', 'How fast tyres cool down', 'How quickly the tyre loses heat to the air and the road (1 is normal).', 0.1, 5, 0.1, 'x'),
  row('temperature', 'sunRoad', 'slider', 'Sun-warmed road', 'How much warmer the road is than the air when the sun shines on it.', 0, 30, 1, 'C', true),

  row('grip', 'coldGrip', 'slider', 'Grip lost when cold', 'How much grip a cold tyre loses (0 none, 1 normal, 2 twice as much).', 0, 2, 0.05, 'x'),
  row('grip', 'hotGrip', 'slider', 'Grip lost when overheated', 'How much grip an overheated tyre loses.', 0, 2, 0.05, 'x'),
  row('grip', 'pressureEffect', 'slider', 'Effect of tyre pressure', 'How much the pressure changes grip and wear (0 none, 1 normal).', 0, 2, 0.05, 'x', true),
  row('grip', 'beltGrip', 'slider', 'Grip with no tread (rolling)', 'The grip of a tyre worn down to its belts.', 0.2, 1, 0.01, nil, true),
  row('grip', 'beltSliding', 'slider', 'Grip with no tread (sliding)', 'The grip of a belt-worn tyre that is sliding.', 0.2, 1, 0.01, nil, true),

  row('wet', 'rainCool', 'slider', 'Cooling by rain', 'How much faster a tyre cools on a fully wet road.', 1, 10, 0.5, 'x', true),

  row('fire', 'fires', 'bool', 'Tyre fires', 'A tyre that gets hot enough catches fire.'),
  row('fire', 'fireSpread', 'bool', 'Fires can spread to the car', 'A tyre fire that burns long enough lights the nearest part of the car.'),
  row('fire', 'spreadAfter', 'slider', 'Seconds before the car catches', 'How long a tyre fire burns before it lights the car.', 1, 20, 1, 's', true),
  row('fire', 'smokeOn', 'slider', 'Smoke starts at', 'The tyre temperature where smoke starts.', 80, 400, 5, 'C', true),
  row('fire', 'smokeFull', 'slider', 'Full smoke at', 'The tyre temperature where the smoke is thickest.', 80, 400, 5, 'C', true),
  row('fire', 'igniteT', 'slider', 'Fire starts at', 'The surface temperature that sets the tyre alight.', 200, 600, 10, 'C', true),
  row('fire', 'igniteHold', 'slider', 'Seconds it must stay that hot', 'How long the tyre must stay at the fire temperature before it ignites.', 0.5, 10, 0.5, 's', true),
  row('fire', 'burnT', 'slider', 'Temperature of a burning tyre', 'How hot a burning tyre gets.', 400, 800, 10, 'C', true),
  row('fire', 'popAfter', 'slider', 'A burning tyre bursts after', 'Seconds a burning tyre lasts before it bursts.', 2, 60, 1, 's', true),
  row('fire', 'douse', 'slider', 'Rain and water put fires out', 'How strongly rain and water put out a tyre fire.', 0, 3, 0.1, 'x', true),
  row('fire', 'debris.hotFrom', 'slider', 'Rubber thrown off: warm from', 'Below this temperature a tyre throws off only the cool share of its worn rubber.', 50, 400, 5, 'C', true),
  row('fire', 'debris.hotTo', 'slider', 'Rubber thrown off: hot from', 'Above this temperature a tyre throws off the hot share.', 50, 400, 5, 'C', true),
  row('fire', 'debris.pileTau', 'slider', 'Rubber pile cooling time', 'How fast a pile of thrown rubber cools.', 2, 120, 1, 's', true),
  row('fire', 'debris.pileIgniteT', 'slider', 'Rubber pile catches fire above', 'A hot pile of rubber catches fire above this temperature.', 150, 600, 10, 'C', true),
  row('fire', 'debris.pileMinG', 'slider', 'Smallest pile that can burn', 'A pile lighter than this cannot catch fire (grams).', 1, 200, 1, 'g', true),
  row('fire', 'debris.pileBurnS', 'slider', 'Rubber pile burns for', 'How long a burning pile lasts.', 2, 120, 1, 's', true),
  row('fire', 'blowout.enabled', 'bool', 'Blowouts damage nearby panels', 'A tyre that bursts pushes on the body panels beside it. Off until it has been seen working in the game.'),
  row('fire', 'blowout.strength', 'slider', 'Blowout force', 'How hard a burst tyre pushes (it is still capped).', 0, 3, 0.1, 'x'),
  row('fire', 'blowout.radius', 'slider', 'Blowout reach', 'How far from the wheel the burst pushes, in metres.', 0.2, 0.8, 0.05, 'm', true),
  row('fire', 'blowout.maxNodes', 'int', 'Most points pushed', 'How many points of the body a burst tyre pushes.', 1, 8, nil, nil, true),
  row('fire', 'blowout.steps', 'int', 'Steps of the push', 'For how many physics steps the push lasts.', 1, 5, nil, nil, true),
  row('fire', 'blowout.maxForce', 'slider', 'Hardest push on one point', 'A hard cap on the force on one point of the body, in newtons. It cannot be set above 3000.', 500, 3000, 100, 'N', true),
  row('fire', 'blowout.chance0', 'slider', 'Panel damage chance, standing', 'The chance a burst damages panels at a standstill.', 0, 1, 0.05, '%', true),
  row('fire', 'blowout.chance100', 'slider', 'Panel damage chance at 100 km/h', 'The chance a burst damages panels at 100 km/h.', 0, 1, 0.05, '%', true),
}

-- per-compound fields: key -> min, max, step, label, tooltip
local COMPOUND_KEYS = {
  { 'base', 0.5, 1.5, 0.01, 'Base grip', 'Dry grip compared with a road tyre (1).' },
  { 'h0', 2, 20, 0.5, 'Tread depth', 'The tread a new tyre has, in millimetres.', 'mm' },
  { 'margin', 0, 2, 0.05, 'Wear margin', 'How far below zero tread the belts last before the tyre fails.', 'mm' },
  { 'k', 0.02, 1, 0.01, 'Wear rate', 'How quickly this tyre wears: bigger wears faster.' },
  { 'lo', -40, 120, 1, 'Best grip from', 'The temperature where the tyre starts to give its best grip.', 'C' },
  { 'hi', -20, 130, 1, 'Best grip up to', 'The temperature where the tyre starts to overheat.', 'C' },
  { 'grip20', 0.5, 1.3, 0.01, 'Grip at 20 C', 'The grip of the tyre when it is cold (20 C).' },
  { 'drop', 0, 0.1, 0.005, 'Grip lost per 10 C of overheating', 'Grip lost for each 10 degrees over the best grip window.' },
  { 'wearOn', 40, 160, 5, 'Wears faster from', 'The temperature from which the wear climbs.', 'C' },
  { 'dry0', 0.5, 1.3, 0.01, 'Dry grip with no tread', 'Grip on a dry road when the tread is gone.' },
  { 'dryF', 0.5, 1.3, 0.01, 'Dry grip factor', 'A multiplier on dry grip (wet-weather tyres lose some).' },
  { 'wet0', 0.2, 1.3, 0.01, 'Wet grip with no tread', 'Grip on a wet road when the tread is gone.' },
  { 'wetF', 0.3, 1.5, 0.01, 'Wet grip factor', 'A multiplier on wet grip (wet-weather tyres gain).' },
  { 'aqua', 5, 40, 1, 'Aquaplaning speed', 'The speed (metres per second) where the tyre starts to aquaplane in deep water.', 'm/s' },
  { 'loose', 0.3, 1.5, 0.01, 'Grip on loose ground', 'Grip on gravel, dirt and sand, compared with a road tyre.' },
  { 'snow', 0.2, 1.5, 0.01, 'Grip on snow', 'Grip on snow and ice, compared with a road tyre.' },
  { 'crr', 0.005, 0.03, 0.001, 'Rolling resistance', 'How hard the tyre is to roll: bigger is slower on the straight.' },
}

local COMPOUND_ORDER = { 'road', 'performance', 'semislick', 'slick', 'slicksoft', 'drag', 'offroad', 'mud', 'winter', 'rally', 'intermediate', 'fullwet' }

local function title(s) return (s:gsub('^%l', string.upper)) end

-- opts: { rules = the tyre rules (default: require('csfx_tyrerules')), read = function() -> table, write = function(table), reload = function() }
function M.build(S, opts)
  opts = opts or {}
  local R = opts.rules or require('csfx_tyrerules')
  local D = R.defaults()
  local function d(path)
    local t = D
    for part in path:gmatch('[^%.]+') do
      if type(t) ~= 'table' then return nil end
      t = t[part]
    end
    return t
  end
  local function json(path) return { kind = 'json', file = M.FILE, path = path } end
  local reload = function() if opts.reload then opts.reload() end end
  local read = opts.read or function() return (jsonReadFile and jsonReadFile(M.FILE)) or {} end
  local write = opts.write or function(t) if jsonWriteFile then jsonWriteFile(M.FILE, t, true) end end

  local function groupOf(r)
    if r.tab == 'wear' then return r.path:find('^surface') and 'Wear by surface' or (r.path == 'enabled' and 'Tyre simulation' or 'Wear') end
    if r.tab == 'fire' then return r.path:find('^blowout') and 'Blowouts' or (r.path:find('^debris') and 'Rubber debris' or 'Fire') end
    return title(r.tab)
  end
  local fields = {}
  for _, r in ipairs(ROWS) do
    local f = { id = 'ty_' .. r.path:gsub('%.', '_'), tab = r.tab, group = groupOf(r), type = r.type, label = r.label, tooltip = r.tooltip, default = d(r.path), store = json(r.path),
      apply = 'live', onChange = reload, advanced = r.advanced }
    if r.type == 'slider' or r.type == 'int' then f.min, f.max, f.step, f.unit = r.min, r.max, r.step, r.unit end
    if r.type == 'slider' and r.unit == '%' then f.scale = 100 end
    if r.type == 'bool' then f.feature = true end
    fields[#fields + 1] = f
  end

  -- the preset: a choice that writes a whole set of values (the page reloads after it)
  fields[#fields + 1] = { id = 'ty_preset', tab = 'wear', group = 'Tyre simulation', type = 'enum', label = 'Preset',
    tooltip = 'Realistic: the starting values. Arcade: slow wear, mild heat and grip effects, no flat spots, fires or blowout damage. Off: the game\'s own tyres. Choosing one sets the values on these pages; you can change them afterwards.',
    options = { { id = 'realistic', label = 'Realistic' }, { id = 'arcade', label = 'Arcade' }, { id = 'off', label = 'Off' } }, default = 'realistic', apply = 'live',
    store = { kind = 'custom', get = function() local v = read().preset return M.PRESETS[v or ''] and v or 'realistic' end,
      set = function(v)
        if not M.PRESETS[v] then return end
        local t = M.merge(D, M.PRESETS[v])
        t.preset = v
        write(t)
        reload()
      end } }

  -- the share of worn rubber thrown off as debris: one slider that scales the cool and the hot share together
  local function frac(t, k) return (t.debris and t.debris[k]) or D.debris[k] end
  fields[#fields + 1] = { id = 'ty_debris_amount', tab = 'fire', group = 'Rubber debris', type = 'slider', label = 'Rubber debris amount',
    tooltip = 'How much of the worn rubber is thrown off the tyre as debris (1 is normal, 0 none).', min = 0, max = 1.25, step = 0.05, unit = 'x', default = 1, apply = 'live', onChange = reload,
    store = { kind = 'custom', path = 'debris.amount',
      get = function() local t = read() return math.floor(frac(t, 'maxFrac') / D.debris.maxFrac * 100 + 0.5) / 100 end,
      set = function(v)
        local t = read()
        t.debris = t.debris or {}
        t.debris.minFrac = math.min(1, D.debris.minFrac * v)
        t.debris.maxFrac = math.min(1, D.debris.maxFrac * v)
        write(t)
      end } }

  fields[#fields + 1] = { id = 'ty_visuals_note', tab = 'visuals', group = 'Worn tyres', type = 'note', label = 'Tread stages',
    tooltip = 'The look of a tyre as the tread wears (the stages and the tread fade) has no settings yet. They come with the tyre visuals.' }

  -- the compounds: one at a time, picked in a selector (twelve compounds of sixteen values would be nearly two hundred rows)
  local selected = COMPOUND_ORDER[1]
  local options = {}
  for _, name in ipairs(COMPOUND_ORDER) do if R.COMPOUNDS[name] then options[#options + 1] = { id = name, label = title(name) } end end
  fields[#fields + 1] = { id = 'ty_compound', tab = 'compounds', group = 'Compound', type = 'enum', label = 'Show the settings of this compound',
    tooltip = 'Pick a tyre type and the settings below are the ones for it. The change applies to every tyre of that type.', options = options, default = options[1].id,
    store = { kind = 'custom', get = function() return selected end, set = function(v) selected = v end } }
  for _, name in ipairs(COMPOUND_ORDER) do
    local c = R.COMPOUNDS[name]
    if c then
      for _, k in ipairs(COMPOUND_KEYS) do
        if c[k[1]] ~= nil then
          fields[#fields + 1] = { id = 'ty_c_' .. name .. '_' .. k[1], tab = 'compounds', group = title(name), type = 'slider', label = k[5], tooltip = k[6] .. ' (' .. title(name) .. ')',
            min = k[2], max = k[3], step = k[4], unit = k[7], default = c[k[1]], store = json('compounds.' .. name .. '.' .. k[1]), apply = 'live', onChange = reload, advanced = true,
            visibleIf = { field = 'ty_compound', equals = name } }
        end
      end
    end
  end

  return { mod = 'car_surface_fx_tyres', title = 'Tyres', icon = 'wrench', order = 41, tabs = M.TABS, fields = fields }
end

-- a copy of `base` with `over` laid over it (nested tables merged)
function M.merge(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = type(v) == 'table' and M.merge(v, {}) or v end
  for k, v in pairs(over or {}) do
    if type(v) == 'table' and type(out[k]) == 'table' then out[k] = M.merge(out[k], v) else out[k] = v end
  end
  return out
end

return M
