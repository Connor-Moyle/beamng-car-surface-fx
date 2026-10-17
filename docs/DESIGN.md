# Car Surface FX - design (research result, 2026-10-17)

## What the game gives us (0.39, checked in lua/ and shaders/)
- Vehicle paint/body use the one stock PBR shader (shaders/common/material/shadergen/defaultMat.hlsl). Per layer: baseColor, roughness, clearCoat(+Roughness),
  normal, and **detail maps** (baseColor/normal/roughness/metallic/AO + `detailScale`, factors) sampled by the mesh UVs. No wetness, dirt or world-position input.
- Materials are global objects by name (`scenetree.findObject`, `setField`, `flush`/`reload`): a change hits every car using that material, not just one.
  `veh:getMaterialNames()` lists a car's materials; vehicle/material.lua uses `obj:switchMaterial(msc, newMat)` / `resetMaterials` to swap a material **per vehicle**.
- The dynamic-decal (livery) system is editor-bound and needs per-part `dynDecalMaterials` + the `@DynamicTexture` set: NOT universal. Rejected.
- `Engine.Render.DynamicDecalMgr.addDecal` is world/ground decals, not on cars. Vehicle particles (nodes) and GE particles/imgui overlay exist.

## Options
| Option | Universal | Per-car state | Cost | Verdict |
|---|---|---|---|---|
| A. Edit existing material fields (roughness down, base darker, clearCoat up) | yes | no (global) | low, only on change | **Rain wetness. Use.** |
| B. Add one shared tiling droplet/dirt detail map to each material layer (no per-car textures) | yes (UV-scaled, so looks different per car) | no | low | **Rain beads + dirt grain. Use, check on 4-5 cars.** |
| C. Per-vehicle clone material (`name.sfx`) + `switchMaterial` | yes | **yes** | clone once per material | **Dirt/mud/scratch amount per car. Spike first.** |
| D. Particles on vehicle nodes (running drops, splashes, mud flicks) | yes | yes | budgeted | **Streaks, wheel splash. Use.** |
| E. Screen-space windscreen drops (cockpit camera only, imgui/UI overlay) | yes | n/a | tiny | Phase 1b |
| F. Override defaultMat.hlsl (world-space triplanar, height-gradient dirt, real streaks) | yes | needs uniform | medium | **Only if A-D look weak; risky (breaks on game update, other mods).** |

## Plan
1. Spike (needs manager to run, ~5 min): on the player car, snapshot a material's fields, set roughness/baseColor/detail map, flush, screenshot; time it; try C (clone + switchMaterial on one car with a second car sharing the material). This decides whether dirt/scratches can be per-car.
2. Phase 1 rain: A + B for wetness/beads (intensity = wetness 0..1, drying curve), D for drops blown back / running streaks (rate from speed and wetness), E for glass.
3. Phase 2 dirt: C + B (dirt colour, roughness up), build-up rate from wheel surface (groundmodel under wheels), faster on lower body = per-material split only (lower/bumper/skirt names) since no height mask without F; wash on rain or when a car-wash/water volume is hit.
4. Phase 3 scratches: damage events (`onBeamBroke` / part damage from vehicle Lua) add scratch strength to the per-car material; chips through a roughness+baseColor detail map; persists as long as the car state does.

## Budget / rules
Material edits only when the target changes > 0.02 (throttled 5 Hz), never per frame; preallocated tables; player car only, traffic off by default. Intensity: sl_weather.wetness() if loaded, else core_environment.getPrecipitation() (drops/1000 smoothed up, drying down).
Settings: mod/settings/carSurfaceFx.json (per effect on/off + intensity). Debug: `carSurfaceFx.debug('rain',1.0)`, `('mud',0.8)`, `('scratch',1)`, `debug()` clears.
Layout: mod/lua/ge/extensions/carSurfaceFx.lua (+ carSurfaceFx/*.lua), tools/ (droplet/dirt tiling texture generator, selfcheck), tests/.

## Risks
Material is global (A, B): all cars share wetness (fine for rain). Detail-map tiling follows each car's UV scale. Flush/reload cost is unmeasured. Streak "merging drops" is particles only, not on-paint, without F. Cars whose layers already use detail maps keep theirs (we only fill empty slots).
