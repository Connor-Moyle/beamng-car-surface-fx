# Grass flattening: what BeamNG 0.39 gives us, and our own implementation (design)

Reference for the wish: the community mod "Dynamic grass" (beamng.com thread 111830). This note is written from the game's own files and binary only; nothing of that mod's code or assets is used or needed. Verified items are read from `I:\SteamLibrary\steamapps\common\BeamNG.drive` (shaders, Lua, strings of `Bin64\BeamNG.drive.x64.exe`); items marked **TEST** need a game run (`carSurfaceFx/grassProbe.lua` on this branch does them).

## 1. The key finding: the game already has it

BeamNG 0.39 contains a complete grass flattening and cutting system, built into the engine and used by no menu or default script. The pieces:

**The ground cover shader reads a mask.** `shaders/common/foliage.hlsl` (the vertex shader of GroundCover billboards) samples a texture `gc_surfaceMask` at the blade's world position. Four channels:
- `rg`: the direction the blade leans away to (stored as 0..1);
- `b`: flatten, 0..1: removes that fraction of the blade's height (`outPos -= up * upAmount * flatten`) and pushes the top corners along the direction by `gc_surfaceMaskParams1.x` metres ("grass bend meters");
- `a`: cut. At 0.95 to 0.99 the blade fades out completely (`cutAmount = smoothstep(0.95, 0.99, a)`, alpha x (1 - cut)): mown or uprooted grass.
Only the upper two corners of the billboard (`corner > 1`) bend, so the roots stay. The mask is a window around the player (`gc_surfaceMaskParams0`: origin, inverse size, enabled flag) that wraps like a toroidal clipmap and fades at its edge.

**A compute shader paints it.** `shaders/common/surfaceMaskClipmap.cs.hlsl`: stamps are `circle` (centre, radius, radial or given direction) and `line` (start, end, width; the direction is away from the line), each with `flatten` and `mark` (cut). A new stamp keeps the stronger of old and new per channel (`max`), so stamps only ever add: **there is no regrowth** and no per-region clearing.

**Lua can use it.** The engine global `SurfaceMaskClipmap` (found in the executable's Lua bindings; its use is shown in `lua/ge/extensions/util/surfaceMaskWheels.lua`, shipped with the game, off by default) has:
- `init(dir)`: tile storage per level; the game's own script uses `/temp/levels/<level>/dynamicTiles`;
- `setCenter(x, y)`: where the window is (follows whatever the script follows; one centre);
- `maskCircleWorld(x, y, radius, flatten, mark)`;
- `maskLineWorld(x1, y1, x2, y2, width, flatten, mark)`;
- `clear()`: the whole mask;
- `setDebugEnabled(bool)`, `getDebugState(pageX, pageY)` (resident pages, pending masks and loads, GPU dispatch time and texels, disk reads and writes, saved pages), `imGuiDrawPageMap`, `imGuiDrawInflightSaves`.
Pages are 16 m squares; dirty pages evicted from the window are saved to disk under the level's temp folder and come back when the player returns.

**Already usable:** `extensions.load('util_surfaceMaskWheels')` (it loads itself with `util_lawnMower` too) stamps the player car's wheels: a line per wheel per 0.05 s, width 1.8 m, flatten 1, mark 0.75 (below the cut threshold, so tyres flatten but do not cut), and a lawn mower prop can cut (mark 1). So a basic "grass bends under the car" is one `extensions.load` away. Our job is to do it better and to settings, not to find a way in.

What the engine does not give: wind per blade (the wind is global constants `gc_windDir`, gust and turbulence from the environment; the sway is the same for all grass), bending by the car's body, regrowth, any other cover than GroundCover billboards (the older `fxFoliageReplicator` and trees use other shaders, untouched), the bend distance setting (`gc_surfaceMaskParams1.x` comes from the engine; no Lua name seen for it).

## 2a. Built (branch worker-a-grass)

- `carSurfaceFx/grassRules.lua`: the rules (stamp width = the tyre's axle width x 1.6 x the setting, 0.35 to 1.4 m; flatten 0.6 to 1.0 by speed x strength; cut when the wheel watcher reports 35% or more slipping; grass by terrain material name (grass, meadow, lawn, turf); a log of stamps for the let-go policy). Tested in `tests/grass_test.lua`.
- `carSurfaceFx/grass.lua` (extension `carSurfaceFx_grass`, started by `carSurfaceFx` while `settings.grass.enabled`, on by default): GE only, no car-side Lua. Stamps the player's wheels every 0.05 s and other cars within the distance (default 60 m, at most 6) every 0.1 s, only where the terrain material under the wheel is grass; takes the clipmap over from the game's `util_surfaceMaskWheels` (switches it off every second, gives it back on unload); `init` per level, `setCenter` on the player; the slip comes from `carSurfaceFx.onGround` (the wheel watcher, every 0.5 s).
- Regrowth: the mask cannot fade, so "let trails go after N minutes" clears it and puts the recent stamps (within 150 m, up to 1500) back, 150 a tick; "clear when a level loads" (default on); `carSurfaceFx_grass.clear()`.
- Mods menu: `carSurfaceFx_grass.fields(file)` returns the Grass tab's fields (enabled, how flat, track width, wheelspin cut, other cars and distance, clear at level, let go after N minutes, a clear-now button) with `TAB`; they store under `grass` in the settings file. Wiring them into Car Surface FX's schema is ba's.
- Not built yet: **body drag** (a flattened line where the underbody scrapes the ground) needs the body-scrape detection of the ported scrape marks (P5); `grass.lua` will get a `drag(id, ...)` call from there.

## 2. What our version adds (module `carSurfaceFx/grass.lua`)

The game's script is one width, one strength, player car only. Ours, using the same global, our own code:

1. **Per wheel, from the tyre.** Width = the tyre's width x 1.6 (at least 0.35 m), not 1.8 m of every wheel (a car's four wheels are 1 to 2 m wide together; the game's stamp overlaps into one 3 m smear). Flatten from load and speed (0.6 to 1.0); a wheel spinning or skidding on grass uproots it: `mark` rises with slip toward 1 (bare earth) at wheelspin, so burnouts leave bare strips. The slip and the ground type already come from the wheel watcher (`carSurfaceFxWheels.lua`, `contactMaterialID`, `rules.groundClass`).
2. **Only on grass and loose ground.** Stamp only when the wheel's ground class is grass or loose; on tarmac nothing is stamped, which keeps pages clean and avoids dirty pages being saved to disk for every road driven.
3. **The body.** When the underbody drags (a node collision with the ground, as the body-scrape mark already detects), a line along the car's footprint with flatten 1 and mark 0.6, as wide as the contact.
4. **Other cars.** The window follows one centre, the player: traffic and other cars inside the window (about the resident pages x 16 m around the player) get the same stamps; further ones none.
5. **Both mark kinds follow the settings** in the Mods menu (ba's Car Surface FX tab "Grass"): on/off, width factor, flatten strength, cut with wheelspin, other cars, body drag, "clear the flattened grass when a level loads".
6. **Do not double up with the game's script:** if `util_surfaceMaskWheels` is loaded and enabled, take it over (call `util_surfaceMaskWheels.setEnabled(false)` and remember to give it back on unload).
7. **Regrowth** cannot be done with the stamps (max only). The honest options: none (the default of the game: the track stays until the level reloads), `clear()` at level load (our default), or a timer that calls `clear()` every N minutes (one visible pop when the whole mask empties; off by default). A button "Reset grass" in the menu.

Per tick (0.05 s, as the game's own): for each car near the player, each wheel: one vector transform and, only when the wheel moved 0.2 m since its last stamp, one `maskLineWorld`. Nothing allocates per tick (scratch vectors), as the game's script does.

## 3. Cost and risk

- Lua per tick: the game's own script reports its cost (`getPerformanceStats`); ours is the same order, about 0.01 to 0.05 ms for one car. The GPU dispatch is per dirty rectangle; the clipmap's own `getDebugState` gives `dispatchSubmitMs`, `dispatchedTexels`, `savedPagesLast`, disk times: the probe prints them.
- Disk: dirty pages are written to `/temp` as the window moves. Stamping only on grass keeps that small. **TEST** the writes while driving across a big meadow.
- Where it shows: only GroundCover billboards that use `foliage.hlsl`. A map whose grass is built another way shows nothing. **TEST** on gridmap, Utah, Italy, West Coast (our target map) and Johnson Valley.
- Unknown: the bend distance (`grass bend meters`) and the window size; whether the global exists at all times or only after a terrain is loaded (the game's script checks for it each time).
- The mask persists across respawns until `clear()`.

## 4a. Game steps for the built module (connor-80), on a map with a big grass field (Utah, Italy, West Coast, Johnson Valley, gridmap's grass if it has any)

Install branch worker-a-grass as the mod. Console: `carSurfaceFx_grass.status()` first (it says on or off and what it does).
1. **Before:** park at the field's edge, a shot looking along the field from low behind the car.
2. **A few laps:** drive 3 laps round a loop of 60 m or so on the grass at 30 to 50 km/h, then stop at the same spot and take the same shot from the same place. Also a shot straight down on a track from a high camera. Is the track as wide as the tyres (about 1.5 tyre widths), bent away from the wheel, flatter with more speed?
3. **Donut:** a full-throttle donut on the grass for 10 s. Shot from above: is there a bare ring (grass torn out) where the wheels spun, and flattened grass round it?
4. **Wheelspin launch:** a standing start with the wheels spinning for 3 s: a bare strip at the start?
5. **Tarmac:** drive from the field onto a road and back: nothing stamped on the road (`carSurfaceFx_grass.status()`: the skipped count rises).
6. **Other cars:** with traffic or an AI car driving past you on the grass: does it leave a track too (`carSurfaceFx.enable` is not needed; the setting "other cars" is on by default)?
7. **The game's own script:** `extensions.load('util_surfaceMaskWheels')` after ours: `status()` should report it switched off, and no double-wide track.
8. **Clearing:** `carSurfaceFx_grass.clear()` puts the grass up. Set the "let trails go" time: `carSurfaceFx_grass.configure({ clearAfterMin = 1 })`, wait 2 minutes of driving: do old trails vanish while new ones stay, without a flash of the whole field?
9. **Cost:** `SurfaceMaskClipmap:setDebugEnabled(true)` then `carSurfaceFx_grassProbe.status()` (or `util_surfaceMaskWheels.setDebugMode(1)` for the game's own log line): GPU dispatch ms and texels, pages saved to disk while driving a long way across the meadow, and the frame time with and without (`carSurfaceFx_grass.stop()` / `start()`).
10. Report errors in the log and any visible pop when a purge happens.

## 4. Game steps (connor-80), with `carSurfaceFx/grassProbe.lua`

1. On a map with grass: `extensions.load('carSurfaceFx_grassProbe'); carSurfaceFx_grassProbe.status()`. Reports whether `SurfaceMaskClipmap` exists and whether the game's wheel script is loaded; with `debug(true)` first, the clipmap state.
2. `flatten()` on a meadow: a flattened circle 8 m ahead and a line 14 m long on the right. Shot from behind and at a low angle. `cut()`: the same with grass removed. `fan()`: five circles with flatten 0.3 to 1.0 (the bend direction and strength).
3. `util_surfaceMaskWheels` for the game's own result: `extensions.load('util_surfaceMaskWheels')` and drive in a straight line, then a circle, across grass: shot of the tracks, and the log line `surfaceMask` with the costs (`util_surfaceMaskWheels.setDebugMode(1)`).
4. `clear()` empties it. Reload the level: do the tracks come back from the disk pages?
5. Report the frame time with and without, and any error in the log.

## 5. Order of work

1. TEST (section 4): confirm the global, the look of flatten and cut, and the cost.
2. `grass.lua` with the per-wheel stamps and the settings, a fengari test with a mocked `SurfaceMaskClipmap` (stamp arguments, only on grass, the take-over of the game's script).
3. Body drag, other cars, the clear policy.
4. A Grass tab in the Mods menu (ba), the QA script section with shots.
