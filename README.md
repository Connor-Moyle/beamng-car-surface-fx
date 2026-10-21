# Car Surface FX

Weather and wear on the body of every car, while you drive. It works at runtime on stock and modded vehicles alike: no per-car textures, no per-car setup. This is version 0.4.8 (see CHANGELOG.md).

- **Wet paint.** When it rains the paint gets darker and glossier, and fine water beads form on it. The beads grow and merge as the rain goes on and shrink away again as the car dries over a few minutes.
- **Water on the windows.** Drops land on the glass, merge, and the big ones run down and leave small drops behind. Speed pushes them up the glass, hard braking throws them forward, cornering slides them sideways, and the wipers sweep them off. They dry up when the rain stops.
- **Rain on the windscreen from the driver's seat.** In the driver or onboard camera the drops are drawn on the screen over the windscreen as small lenses, with thin wobbling streaks behind the running ones. More rain means more drops, speed pushes them up, cornering sideways, and each wiper sweep (two blades, only while the car's wipers run; a car without wipers gets them by the rain) leaves a clean arc that fills again.
- **Dirt, in four kinds.**
  - *Dust* builds on dry dirt, gravel and sand and washes off quickly.
  - *Mud* builds on mud and on wet loose ground and stays longer.
  - *Tyre rubber* comes from wheelspin, burnouts and skidding.
  - *Road grime* is a slow film from driving on tarmac, faster in the wet.

  The paint takes the tint of whatever the car has collected, and the gloss goes with it. Dirt splats also build up around the wheel arches.
- **Snow.** When it snows (precipitation with the air below 1.5 C) snow settles as a thick cap on the roof and hood of a car that stands and a thin dusting on the sides, is mostly blown off above 8 m/s, and melts when it is warm (sliding off in sheets). Wheels on snowy ground throw pale grey-white slush low behind them. Rain and a car wash take it off.
- **Frost.** On a cold night (air below 2 C, engine cold) the windows frost over, on the outside glass and on the windscreen in the driver's view. It clears as the engine warms up, and rain clears it too.
- **Bugs.** Fast driving in the dry leaves small dark splats on the nose; rain, water and a car wash take them off.
- **Road spray.** On a wet road a car ahead of you (within 25 m, in your lane, going your way) throws spray on your windscreen: a fine mist and a shower of tiny drops, more the faster and the closer it is, and more from long vehicles such as trucks. Changes with the same switch as snow and frost.
- **Puddle splash.** Driving through a puddle above about 10 m/s throws dirty water up the lower doors, sills and wheel arches on the side whose wheels went through, and a deep puddle at speed throws a sheet of water over the windscreen for a moment.
- **Washing.** Rain washes the dirt off slowly (dust fastest, rubber hardly at all), driving through water and puddles washes it faster, and a car wash takes everything off.
- **Leaks and pools.** A damaged radiator, oil pan or fuel tank drips, and the fluid that is let out leaves a pool on the ground that matches its volume (a radiator emptied in seconds leaves a pool about 0.65 m across), with a sheen on oil.
- **Broken glass.** Windows that break leave piles of shards on the ground (more for a bigger pane), readable on concrete and on dark asphalt.
- **Ground marks.** Skid marks and tyre tracks, drawn only near the camera (at most 300 decals out to 60 m, the nearest first) so they cost little frame time.
- **Scratches.** Hard scrapes against walls and barriers leave real scratch marks where the body touched, in the direction it slid. Scratches stay until the car is repaired; washing never removes them.

## Off by default (switch on in the Mods menu)

These are built and each has its own switch. What has been seen working in the game is listed under "Tested" below; the rest is experimental.

- **Tyres:** wear, heat, grip, smoke, fire, pop, rubber chunks and sparks (Mods > Tyres).
- **Worn paint** (fade, grime, scuffs, rust) on a car's body.
- **Panel damage** (Mods > Car Surface FX > Crash, "Panel damage (test)"): a hit leaves a drawn mark on the paint, a dent with light and shade on metal, cracks on plastic, crazing on fibreglass, a split on carbon.
- **Glass impacts**, **rubber marbles** after a long burnout, fire that spreads to the car.

## Tested in the game (screenshots by our tester)

Leak pools (coolant and oil, with the sheen), glass shards on concrete and asphalt, a real windscreen break and a player's side-window break, snow caps without dark prints, melting snow, pale slush behind the wheels, mud from a wheel spray, worn paint (rust, fade, grime) on light and dark cars and kept over a respawn, tyre chunks in a burnout, panel marks from real wall hits (readable on a black car), and the ground-marks frame-time cut (standing with full rings 2.30 ms to 1.67 ms, marks off 1.06; skid marks stay right out to 55 m).

Not yet tested: the new dent look on red and white paint, a side swipe or a pole hit, carbon and fibreglass panels, marks after a recovery that keeps damage, mud spray trails, the rubber heap and glow, scuffs, grime on dark paint, a side window breaking on other cars, and skid marks on dirt, gravel and snow at the new 60 m distance.

## Install

Copy the `mod` folder's contents into a mod zip (or use `tools\install.ps1` to link the folder into your BeamNG user folder as an unpacked mod named `carSurfaceFx`). The mod starts with the game and keeps running across level loads. Needs BeamNG.drive 0.40.

## Settings

**Mods menu.** The pause menu has a Mods menu (part of Wrench Works) with a Car Surface FX page: tabs for Rain & glass, Dirt & wear, Weather extras, Skid marks & terrain and Textures, every setting with a plain description, a Reset for each tab, and buttons to wash the car or buff out the scratches. Changes apply at once. Without Wrench Works installed there is no menu: the mod runs on its defaults and the settings files below.

**Settings file.** The first start writes `settings/carSurfaceFx.json` in your BeamNG user folder. It gives the start values (the Options page takes over once it has its own values) and has a few more keys than the page. Edit it with the game closed.

| Key | Meaning | Default |
|---|---|---|
| `rain.enabled`, `rain.intensity` | wet paint and beads; 0..1 strength | on, 1 |
| `windscreen.enabled`, `windscreen.intensity` | drops on the windows | on, 1 |
| `windscreen.overlay` | the drops drawn over the windscreen in the driver's view | on |
| `mud.enabled`, `mud.intensity` | show dirt on the paint; 0..1 strength | on, 1 |
| `mud.buildup` | dirt builds up while you drive (off: dirt only appears when another mod or a command sets it) | on |
| `scratch.enabled` | scratch marks and wheel-arch dirt splats | on |
| `scratch.colour`, `scratch.opacity`, `scratch.markSize` | colour of bare metal in a scratch (rgb 0..1), how strongly it shows, length multiplier | grey, 0.9, 1 |
| `scratch.dirtEnabled`, `scratch.dirtColour`, `scratch.dirtOpacity`, `scratch.dirtSize`, `scratch.dirtRate` | the splats around the wheels | on |
| `scratch.allVehicles` | scratch and splat other cars too, not only the one you drive | off |
| `traffic` | apply the effects to every car in the level, not only the one you drive | off |
| `windscreen.overlaySize`, `windscreen.dropSize` | drop size in the driver's view / on the outside of the glass | 4.5, 3 |
| `marks.enabled` | skid marks and tyre tracks on the ground (their own settings are in `settings/carSurfaceFx_marks.json`) | on |

How wet the car gets follows the weather: from Street Legal's wetness when that mod is running, otherwise from the level's rain.

## Console commands (for testing)

Run in the game's Lua console.

- `carSurfaceFx.debug('rain', 1.0)` forces the wetness; `carSurfaceFx.debug('dust'|'mud'|'rubber'|'grime', 0.8)` forces a dirt amount; `carSurfaceFx.debug('wiper', 1)` forces the wipers; `carSurfaceFx.debug('snow'|'bugs', 0.8)` forces the amount of snow or bugs on the car, `debug('snowing', 1)` makes it snow, `debug('frost', 0.8)` forces frost, `debug('air', -5)` forces the air temperature in C, `debug('spray', 0.8)` forces road spray; `carSurfaceFx.debug()` puts the real weather back.
- `carSurfaceFx.wash()` cleans the dirt of your car; `carSurfaceFx.repair()` buffs out its scratches.
- `carSurfaceFx.status()` shows what the mod is doing.
- `carSurfaceFx.debugTools()` loads the debug set (console only, nothing in the menus): `carSurfaceFx_debug.counts()` how many marks, puddles, glass piles and ruts are alive, `.status()` every module's status, `.contacts(true)` a marker at each wheel's contact point, `.surfaces(true)` the ground kind, game material, load and slip at each wheel, `.clearAll()` takes every effect off the ground, `.testAll()` puts one of each in front of the car, `.logging(true)` more log lines.
- `carSurfaceFx.tune('12 12', 0.35)` sets the size and strength of the beads on the paint; `carSurfaceFx.tuneGlass('0 1', 3.0)` sets which direction is down on the glass (`'1 0'`, `'-1 0'`, `'0 -1'` if the water runs sideways or up) and the drop size; `carSurfaceFx.tuneScreen(3)` sets the drop size of the driver's view.

## Other mods

**Enhanced Skid Marks (Surface FX)** by Fatkiwi. The scratch and wheel-dirt engine in this mod is that mod's hi-fi scratch engine, ported over (it is by the same author). Do not run both at once: while Enhanced Skid Marks' own body dirt (`surfaceFXBody`) is loaded this mod pauses, and its scratch engine is not started while Enhanced Skid Marks' own is loaded.

**Street Legal / Wrench Works.** The weather comes from Street Legal's wetness. Other mods can call, with a vehicle id (nothing = the player's car):

- `carSurfaceFx.wash(id, amount)` for a car wash (full clean by default),
- `carSurfaceFx.repair(id)` after a repair or a paint job,
- `carSurfaceFx.puddle(id, depth)` when a wheel goes through a puddle,
- `carSurfaceFx.getState(id)` / `carSurfaceFx.setState(id, state)` to keep a car's dirt and scratches when it is put away and brought back,
- `carSurfaceFx.level(id)` for a readout (`dirtName`: clean, dusty, muddy; `scratchName`: none, light, heavy).

`carSurfaceFx.apiVersion` is 2.

## Modder API (old Surface FX)

Mods written for Surface FX / Enhanced Skid Marks keep working. Car Surface FX provides the same public names (the MODDER_API.md of that mod):

- `surfaceFX.registerModule{ id, name, settingsSchema, onSettingsChanged | getValues + onSet, onAction, onUpdate, onVehicleSpawned }` (also `surfaceFX.register`). The page of the module is now its own entry in the pause-menu Mods menu (Wrench Works must be installed for the page; without it the module still gets its callbacks). The controls map like this: `bool` to a switch, `range` to a slider (an integer stepper with `int`), `colour` to a colour picker, `texturePicker` to a tile grid of the `folder`, `dropdown` to a choice, `button` to a button, `group` to one heading per item.
- `surfaceFXStore.get/set/getAll`: the same file (`settings/fatkiwi_surfaceFX_modules.json`) and layout as before, so saved values carry over.
- `surfaceFXBody.wash()` washes the player's car (same as `carSurfaceFx.wash()`). `surfaceFXBody.dump()` does nothing and logs once; the other old modules (`surfaceFXGlass`, `surfaceFXDebris`, `surfaceFXSparks`, `surfaceFXDebug`...) do not exist: a mod that calls them must guard with `if surfaceFXGlass then`, as the old documentation said.

The old app's own calls (`uiGetModules`, `uiSet`, `uiAction`, `uiSetGroup`, `uiActionGroup`) still exist for a mod that drives them. Do not install the old mod itself next to this one: it is switched off with a message, and these modules take its names.

## Known limits

- **Dents are paint marks, not real dents.** The game's paint layer has no normal map we can change at runtime, so a dent is drawn as a crescent of shade and one of light on the colour map. It reads best in a low sun and is flatter in a straight-on light; the car's shape is changed only by the game's own damage.
- **No water film on the road.** Wet roads are drawn by the map and Street Legal; this mod does not draw one. Heavy rain does lower tyre grip through the physics film when tyres are on.
- The water beads on the paint do not run down the panels; they grow, merge and fade. The drops on the windows do move.
- Wet paint is shared by every car of the same model (they use the same material), so two cars of one model get wet together.
- Windows: the outside of the glass shows the drops clearly. From the driver's seat the inner windscreen pane cannot take the canvas (the game ignores it there), so the drops of the driver's view are drawn on the screen instead and follow the windscreen's outline; the side windows and rear glass show faint rings, and the outer pane is drawn from behind while it is wet.
- Headlight and tail light lenses that share the window material get drops too.
- Scratches are thin (a few millimetres) and look best close up. On cars whose paint uses a real colour-palette texture (several colour zones) scratches can only darken the paint.
- Dirt on the paint is a tint over the whole car; the splats around the wheel arches give it some variation. Splats and scratches are drawn on a 1024 by 1024 canvas per car, so very fine detail is limited by that resolution.
- A car needs its source mesh (`.dae`) next to the game files to get scratch marks; a mod that ships only compiled meshes gets none.

## Credits

Scratch and wheel-dirt engine: Fatkiwi, from Enhanced Skid Marks (Surface FX). Everything else: Connor Moyle.

Dirt, dust, mud and snow splats are made from CC0 photographs from ambientCG (https://ambientcg.com): the list is in docs/TEXTURE_CREDITS.md.
