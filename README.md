# Car Surface FX

Weather and wear on the body of every car, while you drive. It works at runtime on stock and modded vehicles alike: no per-car textures, no per-car setup.

- **Wet paint.** When it rains the paint gets darker and glossier, and fine water beads form on it. The beads grow and merge as the rain goes on and shrink away again as the car dries over a few minutes.
- **Water on the windows.** Drops land on the glass, merge, and the big ones run down and leave small drops behind. Speed pushes them up the glass, hard braking throws them forward, cornering slides them sideways, and the wipers sweep them off. They dry up when the rain stops.
- **Rain on the windscreen from the driver's seat.** In the driver or onboard camera the drops are drawn on the screen over the windscreen as small lenses, with thin wobbling streaks behind the running ones. More rain means more drops, speed pushes them up, cornering sideways, and each wiper sweep leaves a clean arc that fills again.
- **Dirt, in four kinds.**
  - *Dust* builds on dry dirt, gravel and sand and washes off quickly.
  - *Mud* builds on mud and on wet loose ground and stays longer.
  - *Tyre rubber* comes from wheelspin, burnouts and skidding.
  - *Road grime* is a slow film from driving on tarmac, faster in the wet.

  The paint takes the tint of whatever the car has collected, and the gloss goes with it. Dirt splats also build up around the wheel arches.
- **Washing.** Rain washes the dirt off slowly (dust fastest, rubber hardly at all), driving through water and puddles washes it faster, and a car wash takes everything off.
- **Scratches.** Hard scrapes against walls and barriers leave real scratch marks where the body touched, in the direction it slid. Scratches stay until the car is repaired; washing never removes them.

## Install

Copy the `mod` folder's contents into a mod zip (or use `tools\install.ps1` to link the folder into your BeamNG user folder as an unpacked mod named `carSurfaceFx`). The mod starts with the game and keeps running across level loads. Needs BeamNG.drive 0.39.

## Settings

**Options page.** The game's Options page (Graphics) has a *Car Surface FX* group: wet paint and strength, window drops, drops running over the paint, dirt and its build-up speed, scratches and their length, and one switch to apply everything to all cars. Changes apply at once. The group appears after one restart of the game, the first time the mod runs.

**Settings file.** The first start also writes `settings/carSurfaceFx.json` in your BeamNG user folder. It gives the start values (the Options page takes over once it has its own values) and has a few more keys than the page. Edit it with the game closed.

| Key | Meaning | Default |
|---|---|---|
| `rain.enabled`, `rain.intensity` | wet paint and beads; 0..1 strength | on, 1 |
| `windscreen.enabled`, `windscreen.intensity` | drops on the windows | on, 1 |
| `windscreen.overlay` | the drops drawn over the windscreen in the driver's view | on |
| `mud.enabled`, `mud.intensity` | show dirt on the paint; 0..1 strength | on, 1 |
| `mud.buildup` | dirt builds up while you drive (off: dirt only appears when another mod or a command sets it) | off |
| `scratch.enabled` | scratch marks and wheel-arch dirt splats | on |
| `scratch.colour`, `scratch.opacity`, `scratch.markSize` | colour of bare metal in a scratch (rgb 0..1), how strongly it shows, length multiplier | grey, 0.9, 1 |
| `scratch.dirtEnabled`, `scratch.dirtColour`, `scratch.dirtOpacity`, `scratch.dirtSize`, `scratch.dirtRate` | the splats around the wheels | on |
| `scratch.allVehicles` | scratch and splat other cars too, not only the one you drive | off |
| `traffic` | apply the effects to every car in the level, not only the one you drive | off |

How wet the car gets follows the weather: from Street Legal's wetness when that mod is running, otherwise from the level's rain.

## Console commands (for testing)

Run in the game's Lua console.

- `carSurfaceFx.debug('rain', 1.0)` forces the wetness; `carSurfaceFx.debug('dust'|'mud'|'rubber'|'grime', 0.8)` forces a dirt amount; `carSurfaceFx.debug('wiper', 1)` forces the wipers; `carSurfaceFx.debug()` puts the real weather back.
- `carSurfaceFx.wash()` cleans the dirt of your car; `carSurfaceFx.repair()` buffs out its scratches.
- `carSurfaceFx.status()` shows what the mod is doing.
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

## Known limits

- The water beads on the paint do not run down the panels; they grow, merge and fade. The drops on the windows do move.
- Wet paint is shared by every car of the same model (they use the same material), so two cars of one model get wet together.
- Windows: the outside of the glass shows the drops clearly. From the driver's seat the inner windscreen pane cannot take the canvas (the game ignores it there), so the drops of the driver's view are drawn on the screen instead and follow the windscreen's outline; the side windows and rear glass show faint rings, and the outer pane is drawn from behind while it is wet.
- Headlight and tail light lenses that share the window material get drops too.
- Scratches are thin (a few millimetres) and look best close up. On cars whose paint uses a real colour-palette texture (several colour zones) scratches can only darken the paint.
- Dirt on the paint is a tint over the whole car; the splats around the wheel arches give it some variation. Splats and scratches are drawn on a 1024 by 1024 canvas per car, so very fine detail is limited by that resolution.
- A car needs its source mesh (`.dae`) next to the game files to get scratch marks; a mod that ships only compiled meshes gets none.

## Credits

Scratch and wheel-dirt engine: Fatkiwi, from Enhanced Skid Marks (Surface FX). Everything else: Connor Moyle.
