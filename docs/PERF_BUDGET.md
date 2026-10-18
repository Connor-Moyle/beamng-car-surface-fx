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
Steps it does not have, to add before the run: skid marks (with traffic), grass flattening, wheel-arch splats and the body map. Without them the table cannot name where a Max overrun comes from.

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
