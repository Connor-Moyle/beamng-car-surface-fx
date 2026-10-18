# Changelog

## Unreleased (after 0.2.0)

- Bugs and dust (dynamics): bugs depend on the air temperature (none below 8 C, full from 18 C), more at dusk and dawn, none in rain; splats grow as the nose collects more; rain loosens dried bugs slowly at first. Dust also builds as a thin film on dry tarmac, and `rules.dustHeight` / `rules.dustWashHeight` give the film's height and the rain's wash from the top down.
- Wipers: two blades sweep clear arcs on the driver's view (drops, streaks and frost in the arc are gone and the drops bead up again behind them); the window canvases clear their frost in the blade's band. A car with no wiper value gets its wipers from the rain.
- Puddle splash on your own car: dirty water on the lower body by side, a sheet over the windscreen for a deep puddle at speed.
- Road spray from the car ahead on a wet road (mist and tiny drops on the windscreen and the driver's view, scaled by speed, closeness, length and wetness; the nearby cars are looked at four times a second).
- Snow, frost and bugs: see below. (0.2.0 is tagged on the last commit proven in the game; these ship as 0.2.1 once proven.)

- Snow (settles on roof and hood, blows off at speed, melts), frost (glass and the driver's view, clears with the engine), bugs (on the nose after fast dry driving). Options switch "Snow, frost and bugs", settings `weather.snow/frost/bugs`, debug forcing.
- Dirt kinds `snow` and `bugs` join `getState/setState`.

## 0.2.0

- Window drops: a web canvas per car and window material, drops land, merge, run, are pushed by speed and G-force and swept by the wipers; size and density follow the rain.
- Driver's view: the drops are drawn over the windscreen (game web UI layer) as lenses with thin wobbling streaks, clipped to the windscreen's outline, wiper arcs that clear and refill, 30 frames a second at most. Switch: `windscreen.overlay`; `tuneScreen(size)`.
- Drops running over the paint (same canvas as the scratches), driven by gravity, G-force and wind.
- Dirt in four kinds (dust, mud, tyre rubber, road grime) built from what the wheels report, washed by rain, water and car washes.
- Scratches and wheel-arch dirt splats (the hi-fi engine of Enhanced Skid Marks, ported).
- Options page group "Car Surface FX" (Graphics) with live settings.
- API version 2 for other mods: `wash`, `repair`, `puddle`, `getState`/`setState`, `level`.
- Safety: the update loop is wrapped, one error switches the mod off and restores everything.

## 0.1.0

- Wet paint with beads, five wetness levels, drying.
