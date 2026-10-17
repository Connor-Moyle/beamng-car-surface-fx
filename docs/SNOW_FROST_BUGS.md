# Snow, frost and bugs - design note (2026-10-18, before any code)

Three more kinds of weather and wear, built on what exists: the dirt kinds (per-car amounts, tinted paint through `liveUpdateVehicleColors`), the splat layer of the scratch page (marks at body nodes, washed separately from scratches), the window canvases, and the driver's-view overlay.

## What the game gives us (to check before coding)

- Snow weather: `core_environment` has precipitation (rain amount) and a temperature; whether a level exposes "snowing" is the first thing to read in the game's `lua/ge/extensions/core/environment.lua` and the weather presets. If no snow flag exists the mod falls back to precipitation + air temperature below 1 C (`core_environment.getTemperatureK()` if present), and `debug('snow', x)` always works.
- Air temperature: needed for frost. Engine warm-up: the car's own coolant/engine temperature from the vehicle side (`powertrain`/`thermals` streams), reported by `carSurfaceFxWheels.lua` like the wiper state.
- Ground: the ground model `snow` is already a (weak) dust source in `rules.groundClass`.

## Snow

- New dirt kind `snow` (white, cap 1). It builds only while it snows (rate by precipitation), while the car is still or slow; builds first on the roof and hood.
- Where: the splat layer of the scratch page. Nodes whose rest position is in the top part of the body (z above ~75% of the body's height range) and face up get large soft white splats; the paint tint of the kind gives a thin white film everywhere in proportion to the amount. Per-panel snow is therefore only as good as the node map of the car (cars with no `.dae` get the whole-car tint only).
- Blowing off: above ~8 m/s the amount falls with speed (`k * (speed - 8)` per second) and the splats fade in the same way; a heated cabin does not matter. Parked in the snow it stays and melts above 1 C at a slow rate. Rain washes it.
- Cost: no new material, no reload: the same per-car colour update and splat list as the dirt.

## Frost

- Condition: air below ~2 C, clear-ish and humid night, car not running (or cold). Frost amount 0..1 builds at a few minutes per full amount, only on glass.
- Drawn on the window canvases as an additional layer (ice crystals: a dense white noise with edge fringes, opaque at 1), and on the driver's-view overlay as the same layer clipped to the windscreen hull (the overlay is the only thing the driver sees through).
- Clearing: engine temperature above ~40 C, heater/defrost, wipers (wipers clear the blade's arc only, the rest stays) and rain. The clear-up grows from the bottom (the heater vents) as a rising edge, not a fade.
- Debug: `debug('frost', x)`.

## Bugs

- After fast driving (above ~20 m/s) on country ground (not city tarmac: use the ground model class, dry) small dark splats gather on the nose, the front of the hood, the mirrors and the lower windscreen. A few per minute at speed, capped; amount 0..1.
- Drawn like dirt splats (nodes in the front 25% of the body, facing forward) and as dark specks on the overlay near the windscreen's lower edge, and washed by rain, water and car wash; wipers take them off the arc they sweep slowly.
- Debug: `debug('bugs', x)`.

## Order of work and tests

1. Rules (pure): snow/frost/bug build, melt, blow-off, clearing, with tests in `tests/luatest.lua`.
2. State and API: the three amounts join `getState/setState/level/wash`; `apiVersion` stays 2 with new fields only.
3. Paint and splats for snow and bugs (page JS tests next to `scratchjs_test.js`).
4. Frost on glass and overlay (page and overlay JS tests, cost kept under 0.5 ms).
5. Options page: three more controls (snow, frost, bugs), README and changelog.
6. Game proof through connor-80 for each, with debug forcing since weather presets for snow may not exist on every level.

## Not in the first version

- Per-panel snow depth shape (drifts, snow thickness by geometry): the splat layer is a flat mark.
- Snow on the windows' outside canvas beyond frost, and wiper snow build-up.
- Cars without a node-to-texture map get the whole-car tint only.
