# Changelog

## 0.4.11 (2026-10-23)

Changes since 0.4.10. Needs BeamNG.drive 0.40. None of it has been seen in the game yet (the offline tests cover it).

Added:

- Tyres: cold hardening of the rubber by compound: a summer tyre loses about 12 % of its grip at 0 C, a performance tyre about 20 %, a winter tyre almost nothing (three new compound fields on the Tyres page). A test now changes every setting of the Tyres page and every compound field in a scene of its own.
- A body panel scraping along a wall now also leaves a dark scrape on the ground at the wall's foot (part of the gouges, switch "Scrape at the foot of a wall (test)", which are off by default).
- `carSurfaceFx.slotStats()`: how many material reloads and glass canvases the mod has asked for (a console tool for the wet-world work).

Changed:

- Leak puddles: the puddles to draw are picked at most every quarter second (or when the camera moves 2 m or a puddle is added or removed) instead of every frame, and the colours are reused.
- The terrain-deformation probe is dropped (docs/TERRAIN_DEFORM_DECISION.md); the port notes for wall scratches, marks from AI cars and tyre pressure effects are up to date (the last two were already built).

Built, not yet tested in game:

- All of the above: the cold grip numbers (from the research, not measured), the wall scrape on the ground, and the puddle drawing change (its cost with a full ring was already +0.03 ms).
- The open items of 0.4.9 and 0.4.10.

## 0.4.10 (2026-10-23)

Changes since 0.4.9. Needs BeamNG.drive 0.40. This release is mostly fixes found in a code review; apart from the one item under "Proven" none of it has been seen in the game yet (the offline tests cover it).

Proven in the game (connor-80, dirt skid marks at the 60 m distance, johnson_valley):

- Dirt and sand skid marks and tracks: crisp at 5 m, still two thin lines at 30 m, faint near the car at 55 m, fading into the sand further out, with no gap behind the car.

Fixed (covered by offline tests, not seen in game):

- A settings file that is there but cannot be read (locked by a sync or a virus scanner, half written after a crash) is no longer overwritten with the defaults: the defaults run for that session and the file is left as it is. Only a missing file gets the defaults.
- One error in the update no longer switches the whole mod off for the session: it is logged and tried again, five in a row switch it off with a message on the screen, and a new level starts clean. The scratch, decal probe and swatch hooks that had no safety net now have one.
- A report from a car that was destroyed in the same frame (ground, fluids, tyres) no longer brings its tables back.
- Tyres: a NaN or out-of-range number can no longer reach the friction; a tyre saved blown does not throw its tread again when it is loaded; smoke follows the Tyre smoke switch only, not the Tyre fires switch (a change); the unused blowout force settings are removed (the panel marks are unchanged).
- Level end: the lit canvas is destroyed only when the car has one (an engine error line before); the window glass "nothing found" line is a warning only for meshes that have glass-like materials (a character has none); three dead variables removed.
- Quick setup: the draw distance and the decal budget of the skid marks follow the new defaults (40, 60, 80 and 100 m; 100, 300, 500 and 800 decals).

Added (off until another mod calls them; covered by offline tests, not seen in game):

- `carSurfaceFx.setGlassWear(id, { pits, haze })` and `carSurfaceFx.setWiperWear(id, factor)` for Part Wear: pitted and hazy window glass (the player's car), and wiper blades that clear only a share of the drops.
- `carSurfaceFx_tyres.setWearScale(k)` and `getWearScale()`: one career-wide multiplier for the tread wear (session only), for Street Legal's wear rate setting.
- `carSurfaceFx.debug('groundsurface', 'snow')` (or gravel, sand, ice, mud, grass, dirt, tarmac) draws every wheel mark as that surface on any map, so gravel and snow marks can be tested without such a map (`debug()` puts the real surface back).
- The README lists every feature with its switch: ground deformation, grass, the full tyre set, and the hooks above.

Changed:

- Tyre sparks are thrown at 5 m/s (it was 1) for longer streaks. Not seen yet.

Built, not yet tested in game:

- Everything above except the dirt marks; also what the sparks look like, the marbles after a real burnout, cracks from a real hit on plastic, fibreglass and carbon, a pole hit, marks after a recovery that keeps the damage, a side window breaking on other cars, and gravel and snow skid marks (now testable with `debug('groundsurface', ...)`).

## 0.4.9 (2026-10-22)

Changes since 0.4.8. Needs BeamNG.drive 0.40.

Proven in the game (connor-80, stationary camera frames):

- Snow on the sides of a parked car is now a faint dusting of soft translucent flecks (it was hard white blobs), with the thick white cap still on the roof.
- Slush thrown by the wheels on snowy ground reads as pale translucent splashes on a white car, and as off-white splashes on a dark blue car (a little bright there).
- Sparks from a belt-worn tyre: our own spark code fires (the log line appears once for the wheel), nothing fires with the switch off, and the switch has no measurable cost in a burnout (four alternating runs: the script time differs by 0.06 ms, inside the spread).
- Panel marks from real wall hits on metal panels: chips, scratches and crack-like lines on the paint at the place of the hit (a Covet's door, a Vivace's bonnet and fender), readable on a black car. Cracks on plastic, fibreglass and carbon were only drawn by the test command, not seen from a real hit.

Fixed:

- Slush: the paint page draws the snow picture in its own white and never used the colour that was passed, so slush was pure white; it now sits on the light page at a third of the light and slightly grey on the colour page.
- Snow dusting: one faint pass with a faint light instead of three stacked full ones.

Changed:

- Panel damage: the dent shading on metal (0.4.5) is removed, it read as dark blotches. Dents come from BeamNG's own physics, the paint marks from us: chips and scratches on metal and cracks and splits on plastic, fibreglass and carbon. Panel damage stays off by default (test).
- Tyre sparks throw 2 to 6 sparks per tick (it was 1 to 4).
- README: what is on or off by default, what is tested, and the limits (dents are physics; worn paint and scuffs do not show on black paint; no drawn road water film).

Built, not yet tested in game:

- What the sparks look like: only a few specks were seen at 3 m, and in one burnout in place our code did not fire.
- The marbles after a real burnout (only the test hook was used) and their smear.
- Cracks on plastic, fibreglass and carbon from a real hit, a pole hit, marks after a recovery that keeps the damage, a side window breaking on other cars, and skid marks on dirt, gravel and snow at the 60 m distance.
- The slush on a dark car with a bit less light (it is on the bright side on dark blue).

## 0.4.8 (2026-10-22)

Changes since 0.4.7. Needs BeamNG.drive 0.40.

Proven in the game (connor-80, with screenshots and logs):

- The new switches: with Dust, Tyre rubber or Road grime switched off, that kind builds nothing while the others still grow; with Mud off no mud builds on forced mud ground (it rose 0.00 to 0.53 with the switch on); with Tyre smoke off a hot tyre makes no smoke, with it on it does. All six new switches and the masters of the test features are on the Active features page.
- Rubber marbles (test hook with 60 kW on both rear tyres): dark angular bits lie behind the rear axle on both sides and under the car, with tyre smoke, and the patch sits between the wheels (the centre of the two patches, not at one wheel); each patch stops growing near 400 g.
- Belt-worn tyres: the tread no longer loses its tyre force (see Fixed); our own spark code fires on a belt-worn wheel sliding at 4 to 18 m/s (the log line "sparks" appears once for the wheel) and does not fire with the switch off.

Fixed:

- Belt-worn tyres: at the belts stage the tread was switched to metal so that the game would throw its own metal sparks. That made the engine stop the wheel's tyre force altogether (no load, no grip, no slip) and it hid our own spark code, so it is removed. The tread stays rubber at every stage, the belts grip poorly as a tyre (the Belts grip settings), and the sparks come from our own code. The sparks seen in the earlier tests (0.4.x) were the game's metal sparks from that switch, not ours.
- Rubber marbles: the smear's direction is a proper unit vector, a long burnout cannot pass the decal cap, the patch centre is the centre of the rubber thrown (two spinning wheels leave one heap between them), and the smear and the glow are stronger (they were faint).

Built, not yet tested in game:

- What our sparks look like (the camera lost the car in every test), and whether they fire in a burnout in place (they did not in one run: only in a slide).
- The marbles' glow and smear after the change, and a real burnout (only the test hook was used).
- The open items of 0.4.5 to 0.4.7 (the metal dent look on red and white paint, a pole hit, carbon and fibreglass panels, marks after a recovery that keeps the damage, mud spray trails, scuffs, grime on dark paint, a side window breaking on other cars, and skid marks on dirt, gravel and snow at the 60 m distance).

## 0.4.7 (2026-10-22)

Changes since 0.4.6. Needs BeamNG.drive 0.40.

Changed:

- Every part has its own switch in the Mods menu. New switches, all on as before: Dust, Mud, Tyre rubber and Road grime (Dirt page), Tyre smoke and Sparks from belt-worn tyres (Tyres page). A kind that is switched off builds nothing.
- The Active features page now also lists the master switches of the test features (Worn paint, Panel damage, Soil banks beside ruts, Wheels press the ground down, Lit tyre tracks, Gouges). They are off by default and the labels still say test.

Built, not yet tested in game:

- The six new switches (nobody has toggled them in the game yet) and the Active features entries of the test features.
- The open items of 0.4.5 and 0.4.6 (the metal dent look on red and white paint, a pole hit, carbon and fibreglass panels, marks after a recovery that keeps the damage, mud spray trails, the rubber heap and glow, scuffs, grime on dark paint, a side window breaking on other cars, and skid marks on dirt, gravel and snow at the 60 m distance).

## 0.4.6 (2026-10-22)

Changes since 0.4.5. Needs BeamNG.drive 0.40.

Proven in the game (connor-80, with a full set of stored marks, a standing and a driving camera):

- The ground marks cost less: with the skid and track rings full, the frame time standing still was 2.30 ms over the marks-off 1.06, and is 1.67 now; driving was already 1.59 and is 1.52. Skid marks still look right and continuous at 0, 20, 40 and 55 m and when looking back, fading out towards 60 m (asphalt only).

Changed:

- Ground marks: the marks to draw are picked once every tenth of a second (or when the camera moves or turns, or a mark is added) and the same lists go to the engine every frame; before, every frame walked both rings once for each of the 8 surface types. Marks behind the camera are left out.
- Ground marks: at most 300 decals are drawn at once (it was 800) and the cull distance is 60 m (it was 100), and when more are in view the nearest ones are drawn. A saved settings file with the old budget of 800 moves to 300 once (and 100 m to 60 m if it was still the old 100); a player who sets them again afterwards keeps the choice. They are in Mods > Car Surface FX > Skid marks.

Built, not yet tested in game:

- Skid marks on dirt, gravel and snow at the new distance, and a very fast turn of the camera (a flick can leave a gap for up to a tenth of a second).
- The open items of 0.4.5 (how the metal dent reads on red and white paint, a side swipe, a pole hit, carbon and fibreglass panels, marks after a recovery that keeps the damage, mud spray trails, the rubber heap and glow, scuffs, grime on dark paint, and a side window breaking on other cars).

## 0.4.5 (2026-10-22)

Changes since 0.4.4. Needs BeamNG.drive 0.40.

Changed:

- Panel damage (off by default: Mods > Car Surface FX > Crash, "Panel damage (test)"), metal: a hit on a metal panel now draws a dent (a crescent of shade on one side and of light on the other round a faint bowl) with fewer paint chips, where it was a handful of chips that read as dirt. Still texture only, and the light side is a fixed direction on the panel, not the sun.

Seen in the game (connor-80, wall hits at 15 and 60 km/h on a covet and a white and a black vivace):

- Real hits leave marks (counts rise with every hit); on the black car the marks at the front read clearly (lighter streaks and scuffs); a reset that repairs the car takes them off.

Built, not yet tested in game:

- How the new dent reads on red and white paint (the crumpled panel hid it in the first runs), a side swipe along a wall, a pole hit, a carbon or fibreglass panel, and marks staying after a recovery that keeps the damage.
- The earlier list still open: mud spray trails, the rubber marbles heap and glow, scuffs, grime on dark paint, and a side window breaking on cars other than the player's.

## 0.4.4 (2026-10-22)

Changes since 0.4.3. Needs BeamNG.drive 0.40.

Proven in the game (connor-80, with screenshots):

- Melting snow: a melt takes the snow on the car from 0.41 to 0.14 and it holds (81 slides counted).
- Slush on snowy ground is pale grey-white on a blue car (it read tan and brown before); a little low on the sides, round the arches and on the sill. It is a light amount, faint from 3 m and clear up close.

Fixed:

- Slush: the lowest splats are drawn as bigger lumps, and they used the mud picture, which made slush tan. They use the snow picture now.
- Slush stays when snow melts: a melt slides off only the snow lying on the car, not the slush the wheels threw.

Built, not yet tested in game:

- Mud spray trails (the first run was in dark light), the rubber marbles heap and glow, scuffs, grime on dark paint, panel damage from a real hit, and a side window breaking on cars other than the player's (needs the "others" impact setting).

## 0.4.3 (2026-10-22)

Changes since 0.4.2. Needs BeamNG.drive 0.40.

Proven in the game (connor-80, with screenshots):

- Leak pools follow the volume let out: a punctured radiator that dumps its coolant in seconds leaves one pool about 0.65 m across (a deep wet dark green with a soft darker ring) instead of an 8 cm spot, and the oil pool after 40 s parked is one puddle again (radius 0.36), not two at 0.8.
- Glass on asphalt: a car's broken windows leave shards on the ground that read clearly on dark asphalt, with better contrast than on concrete.
- A burnout throws rubber chunks: many flat black angular pieces about 5-10 cm lie on the road behind and beside the tyres, with the white smoke.
- Snow: the dark print-like smudges are gone (the snow picture is lighter); the roof and boot lid carry a clean white cap.
- Worn paint on a dark car: fade is seen a little (lighter, drier, dusty), a respawn with the same config keeps the wear without doubling it, and no values clears it.
- The tyres read the water film in heavy rain and grip less (the film is not drawn on the road: wet roads are Street Legal's job).

Changed:

- Snow: a thin dusting on the sides besides the thick cap on the tops (faint in the first test, made stronger), a lighter snow picture, melting snow that slides off in sheets, and wheels on snowy ground that throw grey-white slush low behind them. Snow ground now has its own class (it was counted as dust).
- Sprayed mud trails off into a few smaller drops, so a spray fans back from a wheel.
- Rubber marbles: a long burnout leaves a visible heap (more and bigger bits and a dark smear), hot rubber glows from 200 C without fire, a blowing tyre throws its tread once, and patches last 15 minutes.
- A destroyed car leaves nothing behind in the mod's per-car tables.
- Console tools: carSurfaceFx.debug('groundmud', 1), debug('groundsnow', 1), debug('melt', f) and carSurfaceFx.snowStatus().

Built, not yet tested in game:

- Melting snow sliding off in sheets, the slush on snowy ground (the first runs were on a respawned car and showed nothing), the stronger snow dusting on the sides, and the mud spray trails (the first run was in dark light).
- The new rubber marbles heap and glow (the earlier version showed only a few dark bits).
- A side window breaking in a real hit (a T-bone at 67 km/h into a parked car broke none).
- Scuffs, and grime on dark paint (too faint to see); worn paint's other effects on other cars.
- Panel damage by part, and panel damage from a real hit.
- Leak puddles with the low cap and the GPU gate (the glossy planes are off by default).

## 0.4.2 (2026-10-21)

Changes since 0.4.1. Needs BeamNG.drive 0.40.

Proven in the game (connor-80, with screenshots):

- Worn paint, rust (off by default; for Part Wear to drive): rust now gathers where water sits, on the lower door and the sill line and around the wheel-arch lips, never above the lower half of the door; many small spots at a low value, more and bigger ones at a high value; each spot is an irregular blob, and some have a run-off stain that wobbles, tapers and fades out. Seen on a white and a brown car at 0.3 and 0.9.
- Oil leaks: the oil pool keeps a near-black glossy look with only a faint pale sheen toward its thin edge, and a soft darker wet ring round the pool.
- Fuel and coolant pools: the fuel pool is a wet dark amber puddle with a wide darker wet ring that reflects the sky at a low angle, like water; the coolant pool is a glossy dark green with a wet look (seen as a close-up).

Changed:

- Rust: placed by the car's own mesh (low, the arch lips, never the underside), with run-off stains running down the body.
- A destroyed car leaves nothing behind in the mod's per-car tables (wipers, paint canvases' node and lightness records, leak reports, panel damage queues). Not yet tested in the game.
- Coolant and fuel pools: a darker tint on the full pool mask, a very smooth surface and a little more metallic.

Built, not yet tested in the game:

- A coolant pool bigger than 8 cm, and the leak pools in rain.
- Rust on a car other than the two tried; at 0.9 the rust on the lower door sits in a band of fairly even height.
- Scuffs; fade and grime on dark paint (the paint canvas can only darken, so they are faint there); worn paint on a respawned dark car.
- Rubber marbles, and panel damage by part (carbon, fibreglass, plastic): off by default.
- Mud after more than about 80 s of driving, and dust on its own.
- Glass piles on asphalt, and a side window breaking in a real hit.
- The chunks a burnout throws, and panel damage from a real hit.
- The water film on the road in heavy rain (Tyres > Wet, off by default).
- Leak puddles with the low cap and the GPU gate (the glossy planes are off by default).

## 0.4.1 (2026-10-21)

Fixes and changes since 0.4.0. Needs BeamNG.drive 0.40.

Proven in the game (connor-80, with screenshots):

- Mud thrown from the tyres on dry loose ground reads as mud again (dark ragged patches over the sand film, heaviest on the lower doors, the rear arch and the rear bumper, roof and bonnet clean). 0.4.0 shipped a tighter height cut that left only an even tan sand film; it is taken out.
- Snow draws on a car that replaced another with the same id (a respawn), and reaches a low bonnet.
- A window that breaks in a real crash leaves shard piles on the ground: a head-on hit into a wall at about 112 km/h broke the windscreen and left two piles spread out in front of and beside the nose (seen on concrete).
- Worn paint (off by default; for Part Wear to drive): on a white car rust, fade and grime at 0.9 are seen, 0.6 is clearly lighter, a reset and a respawn keep it, and switching the setting off or giving no values clears it. On a dark car rust is seen.

Changed:

- Mud: smaller splats with ragged edges from the CC0 photographs, clods use the real mud picture, and the underside (which nobody sees) no longer takes most of the mud. A respawned car starts its dirt build-up over. `carSurfaceFx.debug('groundmud', 1)` makes the wheels run on mud, to test the real build-up on dry ground.
- Snow: the height floor is lower, so a low bonnet gets snow.
- Worn paint: the places are picked on the visible body (almost all of them landed on the underside before), more of them, with stronger fade, grime and scuffs.
- Glass: a big pane leaves one to four piles by the number of its broken beams, spread out the way the glass fell; a small window one.
- The overlay test counts canvas calls instead of timing a frame.

Built, not yet tested in the game:

- Scuffs; fade and grime on dark paint (the paint canvas can only darken, so they are faint there); worn paint on a respawned dark car.
- Rubber marbles, and panel damage by part (carbon, fibreglass, plastic; marks on parts the paint map does not know): off by default.
- Mud after more than about 80 s of driving, and dust on its own.
- Glass piles on asphalt, and a side window breaking in a real hit.
- The chunks a burnout throws, and panel damage from a real hit.
- The water film on the road in heavy rain (Tyres > Wet, off by default).
- Leak puddles with the low cap and the GPU gate (the glossy planes are off by default).

## 0.4.0 (2026-10-21)

Needs BeamNG.drive 0.40.

Proven in the game (connor-80, with screenshots):

- Tyres: wear and heat in a burnout, white smoke, rubber debris, sparks, fire and pop, the worn tyre look, compound swap, wet grip, aquaplaning, fire spread to the car (with the option on), tyres renewed by a reset.
- Dirt: mud thrown from the tyres by driving on loose ground reads as mud (low on the body, a dark rear with drips); snow on the roof, bonnet and boot, also on a car that replaced another with the same id.
- Crash effects (off by default): flying debris at the foot of a wall, sparks, and a broken window leaves a pile of shards on the ground (seen on concrete).
- The window rule: the car's side and rear glass is found from its own parts, and a glass break leaves a pile once.

Built, not yet tested in the game:

- Worn paint (below), rubber marbles, and panel damage by part (carbon, fibreglass, plastic; marks on parts the paint map does not know): all off by default.
- Mud after more than about 80 s of driving; the tightened mud height cut; dust on its own.
- Glass breaking in a real car-to-car hit, and glass piles on asphalt.
- The chunks a burnout throws, and panel damage from a real hit.
- The water film on the road in heavy rain (Tyres > Wet, off by default).
- Leak puddles with the new low cap and the GPU gate (the glossy planes are now off by default).

### Details

- Leak puddles: the glossy puddle planes are now **off by default** (Leaks & puddles page, "Glossy puddles"; a saved profile keeps its own choice) and capped low when on: at most 12 planes at once (slider up to 40, was 60 and 200), only within 40 m of the camera, one plane made and at most two taken away per quarter second. The planes wait a second after any of the mod's own material reloads, through the same gate Street Legal's rain puddles use when that mod is there (planes and shader reloads together are the suspect in a graphics-card crash), and our own small gate without it. The drips and flat puddle decals are unchanged.

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
