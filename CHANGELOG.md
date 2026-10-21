# Changelog

## Unreleased

- Tyres (new, **off by default**, switch it on on the Tyres page of the Mods menu): each tyre is a ring of tread sections that wear, heat and grip separately. Wear comes from sliding (locked wheels leave flat spots and a shake, wheelspin and cornering wear faster), the tread depth and compound (road, performance, semi-slick, slick, drag, off-road, mud, winter, intermediate, full wet, rally) set the grip, temperature changes grip, rain changes grip per compound and a worn tyre aquaplanes earlier. By the tyre model (not yet measured in the game) a road tyre lasts about 40,000 km of plain driving and a full burnout wears it to the belts in about 1.5 minutes; the "Wear while driving" and "Wear speed" settings change that. Hot tyres smoke, can catch fire and pop; worn rubber leaves debris (seen in the game). A worn tyre looks worn, and the belts show once the tread is gone (on the stock tire, tire_01a and tire_01f materials only; the look needs a respawn after you switch the tyres on), and belts sliding on the road throw small sparks. The fire can spread to the car only if you turn that on (off by default), and heavy rain puts a film of water on the road only if you turn "Aquaplaning in heavy rain" on. Every value is on the Tyres page (presets Off, Arcade, Realistic); other mods can read the tyres and swap compounds through the `carSurfaceFx_tyres` extension.

- Worn paint (new, **off by default**, **not yet tested in game**): `carSurfaceFx.setPaintWear` puts a steady fade, grime, scuff and rust layer on a car's paint, for the Part Wear mod to drive. Switch: Worn paint (test) on the Dirt page. See docs/PAINT_WEAR.md.
- Tyres page: switches and settings that were missing. **Rubber debris** has its own on/off switch, and the **worn tyre look** has one too (off: the car's own tyre material) with one setting, the tread left below which a tyre looks worn (the look has three steps: new, worn, belts); it applies to cars spawned after you switch the tyre simulation on. The page's note "no settings yet" is gone. Every value row on the page is read by the tyre rules.
- Tyres page: three more switches, one per part: **Tyres wear out**, **Temperature changes grip** and **Rain changes grip** (off: the tyre grips the same wet or dry, and cannot aquaplane). Every switch on the page also shows on the Active features tab.

## 0.3.0

Proven in the game (connor-80, with screenshots):

- Leaking fluids: oil (black, glossy, faint marbled rainbow sheen), coolant (green) and fuel (amber) as glossy puddles on the ground, growing over time (r 0.32 to 0.56 m in 120 s), real leaks from a hard crash, tyre grip loss in oil, the oldest puddle shrinks away at the cap (default 100). Drip spots of a moving leak are decals.
- Driver's view rain: lens drops and streaks clipped to the windscreen, about 1 ms a frame.
- Wet paint look: darker, with beads; plastic trim gets a softer version (no chrome look).
- Dirt: dust film, tyre rubber splatter near the arches, mud, skid marks on dirt, car wash.
- Window drops seen wet from 4 m.

Built, not seen in the game (these look or behave unconfirmed; the new defaults are below):

- Window drops (the side and rear glass canvases): the haze is gone but the drops were not clearly visible at real size, so they are off by default (Mods menu, Rain & glass, Windows). The driver's-view drops are separate and stay on.
- Wiper sweep (the blades move; the clearing is only weakly visible), drop trails at speed, impact rings, bead animation.
- Falling leak drops are only simulated (invisible: the oil pan is 20 cm above the ground); the sky is not reflected in puddles (engine limit).

Off by default (switch on in the Mods menu once you have tried them):

- Window drops, grass bending (the counters run, the picture was not seen), ruts, snow, frost, bugs, road spray from the car ahead, and crash effects (shards, debris, sparks). Saved profiles keep what they had.

Notes:

- The ring size default is now 100 puddles; a saved profile keeps its old value (60).
- New Mods-menu rows: glass amount, leak planes, oil sheen, grip loss.

## Not yet tested (older notes)

### Built, not yet tested in game

- Bugs and dust (dynamics): bugs depend on the air temperature (none below 8 C, full from 18 C), more at dusk and dawn, none in rain; splats grow as the nose collects more; rain loosens dried bugs slowly at first. Dust also builds as a thin film on dry tarmac, and `rules.dustHeight` / `rules.dustWashHeight` give the film's height and the rain's wash from the top down.
- Wipers: two blades sweep clear arcs on the driver's view (drops, streaks and frost in the arc are gone and the drops bead up again behind them); the window canvases clear their frost in the blade's band. A car with no wiper value gets its wipers from the rain.
- Puddle splash on your own car: dirty water on the lower body by side, a sheet over the windscreen for a deep puddle at speed.
- Road spray from the car ahead on a wet road (mist and tiny drops on the windscreen and the driver's view, scaled by speed, closeness, length and wetness; the nearby cars are looked at four times a second).
- Snow, frost and bugs: see below.

An item moves to "Passed in the game" only when connor-80 posts a pass for it.

- Debug tools (port P16): `carSurfaceFx.debugTools()` and the `carSurfaceFx_debug` console set (counts, status, wheel contact markers and ground labels, clear all, test all). See the README.
- Old modder API (port P15): `surfaceFX.registerModule`, `surfaceFXStore` and `surfaceFXBody.wash` keep working; a module's settings page appears in the Mods menu. See the README.
- Ruts (port P4): loaded wheels on mud, snow, sand, dirt and gravel leave ruts that are deeper with a heavy car and soft ground, and deepen on each pass along the same track (up to a limit). Drawn as small lit road decals with the new mark materials, or as ground decals (a setting; ground decals are also used on their own if the lit way cannot be made in a level). Mods-menu tab "Ruts".
- Map-maker surface names (port P12): `/dirtSkidMarks/*.json` (the old format) and `/carSurfaceFx/*.json` map a map's ground materials to our surface kinds; unknown materials are guessed by name.
- Texture folders (port P13): drop `puddle*.png` in `art/decals/fluids/` or `shards*.png` / `chip*.png` in `art/decals/impacts/` and pick them in the Mods-menu texture-tile fields.
- Crash effects (port P9-P11): glass shard piles where a window broke, pieces of trim, plastic and metal thrown off by a breaking joint or a hard hit (they fly, bounce, settle on the road and are cleaned up after a time or a distance), and sparks where metal grinds on a hard surface; leaking fluids now fall as visible drops before they make a spot. Settings in the Mods menu tab "Glass, debris & sparks" and "Leaks & puddles".
- Snow on the car (roof and hood, blown off at speed, melts), frost on the windows and the driver's view (clears with the engine), bugs on the nose after fast dry driving; dirt kinds `snow` and `bugs` in `getState/setState`.
- Wipers: two blades sweep clear arcs on the driver's view; the window canvases clear their frost in the blade's band; a car without a wiper value gets its wipers from the rain.
- Road spray from the car ahead on a wet road, and puddle splash on your own car (dirty water on the lower body by side, a sheet over the windscreen for a deep puddle at speed).
- Mud and dust that read as dirt: splatter low on the body and around the wheels, with a weaker whole-car tint.
- The driver's view while driving: the windscreen's place is rebuilt from the car's own position (the camera lags a frame), and diagnostics for it.
- Dirt build-up on by default, with a one-time migration of an old saved "off".
- Skid marks and constant tyre tracks per surface (dirt, sand, gravel, mud, grass, ice, snow, tarmac), with an option to replace the game's own marks; ported from Surface FX (Enhanced Skid Marks).
- Leaking fluids: oil, coolant and fuel drips and puddles from a damaged car's real leak rates, and tyre grip loss in puddles (off by default).
- Grass that bends under the wheels, using the game's own surface mask.
- The Mods menu page: every setting in tabs (Rain & glass, Dirt & wear, Weather extras, Skid marks & terrain, Leaks & puddles, Grass, Textures), replacing the Options-page group.
- The old Surface FX / Enhanced Skid Marks mod is switched off when it is loaded too, and the player is told to remove it.

### Passed in the game

- (nothing yet from this list)

### Still to come from the Surface FX port

Body scratches rewritten fresh, ground gouges, wall scratches, ruts, glass piles, crash debris, sparks, map-maker surface names and the old modder API shim.

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
