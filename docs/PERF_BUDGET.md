# Car Surface FX: frame-time budget and quality tiers

Goal: the Max preset costs no more than +3 ms of frame time over "everything off", in heavy rain with traffic.
Status: the budget column is a proposal. The measured column is empty until connor-80 runs the bench (below). Only the body-map build time is measured so far.

## How it is measured

`carSurfaceFx_bench` (`mod/lua/ge/extensions/carSurfaceFx/bench.lua`) switches the effects on one after the other from everything off and records frame time per step, plus the time the mod's own Lua takes. The rest (canvases, texture uploads, GPU) is the difference.

Run (connor-80, driver camera, steady speed, heavy rain with traffic):
1. `extensions.load('carSurfaceFx_bench')`, `carSurfaceFx.debug('rain', 1)`
2. `carSurfaceFx_bench.run()` (about 100 s), then `carSurfaceFx_bench.report()`; also written to `settings/csfx_bench.txt`.
3. Repeat once per preset (performance, balanced, quality, max), same route.
4. Repeat the Max run twice more with Drivers `setDriverRig('flex')` and `setDriverRig('props')`, everything else equal. Reset to `'props'` afterwards.

Steps the bench has today: paint canvases, rain drops on the paint, window canvases, cockpit overlay, dirt and mud, frost and snow, bugs and road spray.
Steps added since: skid marks and leaks. Still missing: grass flattening (off by default), wheel-arch splats and the body map. Without them the table cannot name where a Max overrun comes from.

## Console step list for connor-80 (the full run)

Setup: West Coast, the covet, traffic on, heavy rain. Lighting frozen at noon. Nothing else running on the GPU (no Ollama). Open an admin terminal beside the game for `nvidia-smi`.
1. In the game console: `extensions.load('carSurfaceFx_bench')`, `carSurfaceFx.debug('rain', 1)`. Fill the puddle ring for the leak step: drive a leaking car or run `for i = 1, 100 do carSurfaceFx_fluids.puddleAhead('oil', 3 + i * 0.7, 0.6) end`, then check `carSurfaceFx_fluids.status()` shows about 100 puddles.
2. Cockpit run: driver camera, drive the same straight at a steady 14 m/s (or the AI on the dirt circuit). `carSurfaceFx_bench.run()` (about 125 s, 10 steps of 5 s settle and 7 s measure). When it ends, `carSurfaceFx_bench.report()`. The table has avg ms per frame, p95, p99 ("1% low"), the mod's own Lua ms. Copy `settings/csfx_bench.txt` to the report.
3. At the end of each run, in the admin terminal: `nvidia-smi --query-gpu=memory.used --format=csv`. Take it once at the start of step 2 (everything off) and once at the end (everything on), and report both.
4. Chase camera run: the same, camera on chase (`be:getPlayerVehicle(0)` stays the same), repeat steps 2 and 3.
5. Lit dirt: `carSurfaceFx.set('scratch.dirtGlow', true)`, respawn the car, repeat step 2 once (cockpit camera). Set it back to false and respawn afterwards.
6. 512 against 1024 window canvas: `carSurfaceFx.set('windscreen.canvasSize', 512)`, respawn, repeat step 2; then `...canvasSize', 1024)`, respawn, repeat.
7. Sky Light wet tarmac on and off (the Sky Light mod's own Mods-menu switch for wet tarmac): repeat step 2 once with each, everything else equal.
8. Reset every setting you changed, and the game to the normal car, when done.

The report to bring back: one table per run (avg, p95, p99, the Lua ms per step), the two VRAM numbers per run, and the camera and traffic count used.

## Budget table (Max preset)

| Feature | Proposed cap (ms) | Measured by 80 (ms) | Main knobs |
|---|---|---|---|
| Paint canvases (marks, scratches, water drops) | 0.8 | | paint page throttle (90 ms), canvas size (1024), other cars with canvases |
| Glass page and window canvases | 0.5 | | glass throttle (70 ms), glass_fine (1024 canvas) |
| Cockpit overlay | 0.4 | | overlay_size, overlay drop count |
| Dirt, mud, snow, frost layers | 0.4 | | dirt texture layers, body map size, dirt_speed |
| Skid marks and ruts | 0.4 | | cull, max_drawn, skid_count, track_count |
| Grass flattening | 0.3 | | grass_distance |
| Body map | ~0 per frame (built once at spawn) | | grid N |
| Total | 3.0 | | |

Body map build, measured on the covet (LuaJIT, the game is about 1.5 to 2x slower; this is the build only, not the per-frame cost):

| Grid N | Cells | Build | Memory |
|---|---|---|---|
| 64 (today) | 2,452 | 0.06 s | +1.3 MB |
| 96 | 5,420 | 0.04 s | +2.5 MB |
| 128 | 9,526 | 0.04 s | +4.4 MB |
| 192 | 21,302 | 0.03 s | +9.8 MB |
| 256 | 37,682 | 0.05 s | +17.2 MB |

Reading the .dae takes about 1.3 s once (only at spawn). N=128 is safe on cost and memory; the per-frame cost of more cells (more samples per dirt update) is not measured.

## Existing tiers (schema.lua PRESETS, performance / balanced / quality / max)

- Glass at 1024: off, off, on, on. Cars with effects: player only for the first three, all cars at Max.
- Overlay drop size: 6, 4.5, 3.5, 3.
- Mark cull distance 60, 100, 140, 200 m; max drawn 300, 800, 1200, 2000; skid count 800 to 5000; track count 1000 to 8000.
- Other cars with effects: 0, 6, 8, 12 within 40, 120, 150, 200 m.
- Leaks, grass distance (30, 60, 90, 120 m) and the crash-debris counts scale the same way.

## Proposed additions so the tiers cover the new work

| Knob | performance | balanced | quality | max |
|---|---|---|---|---|
| Paint page update interval | 140 ms | 90 ms | 70 ms | 50 ms |
| Glass page update interval | 110 ms | 70 ms | 55 ms | 40 ms |
| Body map grid N | 64 | 64 | 96 | 128 |
| Dirt layers drawn | film + clods | + dust | + streaks | + splash fans |
| Raindrop impact rings (`imp`) | off | off | on, paint only | on, paint and glass |

If the measured Max total is over +3 ms, drop in this order: impact rings, splash fans, other-car range, the Max update intervals back to the Quality ones. Each is one preset value.

## Risks

- The caps above are guesses until the bench runs; the shares may move a lot (glass and overlay are canvas uploads, which the Lua timer cannot see).
- Faster update intervals raise canvas upload cost in proportion; the Max intervals are the first thing to revert if the glass step overruns.
- Drivers flex vs props is not a CSFX cost; it is measured to separate it from the CSFX table.
