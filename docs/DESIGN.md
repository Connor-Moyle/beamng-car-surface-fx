# Car Surface FX - design (as built, 2026-10-18)

Universal weather and wear on the body of every car, at runtime, with no per-car textures. This replaces the first research note; what was tried and found is in the last section.

## Parts

| Part | Where | How |
|---|---|---|
| Wet paint | `carSurfaceFx.lua`, `rules.lua` | The paint materials of the car are edited in place (darker, glossier, a shared bead normal map as detail map), one material reload per change, 5 wet levels with 5 bead maps (`art/surfacefx/dropletsN.normal.png`, made by `tools/gen_droplets.py`) so beads appear, grow and merge with wetness and fade as it dries. Originals are read once per material and put back on dry, level change and unload. |
| Window drops | `vehicles/common/carSurfaceFx/glass.html`, `glass.js`, `sim.js` | A web canvas per car and window material (`@csfx_<material>`), created before the material points at it. The outside glass takes it as its base colour map: the page draws the glass's own tint image first (path in the URL) and the drops on top (they land, merge, run, are pushed by speed and G-force, the wipers sweep them). The inside glass takes it as its emissive map. Only colour-type slots resolve `@tags`. |
| Dirt | `rules.lua`, `carSurfaceFxWheels.lua` | Four kinds (dust, mud, tyre rubber, road grime), each with a tint, built from what the wheels report (ground model class, skidding, water) and washed by rain, water and `wash()`. Applied through the car's own paint data (`liveUpdateVehicleColors`, the paint shop's call): per car, no reload. |
| Scratches, dirt splats | `carSurfaceFx/scratch.lua`, `meshuv.lua`, `scratch.html/js` | The hi-fi engine of Enhanced Skid Marks (same author) folded in: node-to-texture map read from the car's `.dae`, per-car canvases bound in place to the paint layer's base colour and palette maps, hit reports from the vehicle (`carSurfaceFxScratch.lua`). Scratches and splats are separate lists on the page (washing fades splats only, repair removes scratches only). |
| Paint drops | `scratch.js`, `paintwater.js` | Rain drops running over the paint in the same canvas, in the texture's UV space; "down" at a place comes from the node map's Jacobians and the force on the water (gravity, car acceleration, wind). |
| Driver's view overlay | `carSurfaceFx/screen.lua`, `tools/overlay/overlay.js`, built into `ui/modModules/csfxRain/csfxRain.js` by `tools/build_overlay.js` | The vivace's inner windscreen pane cannot show a canvas, so in the driver/onboard camera the game's web UI layer (a global UI module, like the Street Legal HUD) draws the drops: a transparent full-screen canvas clipped to the windscreen's outline, which Lua projects from the flexbody's nodes (`_group_nodes` of the mesh named windshield/windscreen) about 15 times a second (`guihooks.trigger('csfxScreen', ...)`). The drop simulation is the window one (`sim.js`). |
| Career hooks | `carSurfaceFx.lua` | `apiVersion` 2: `wash`, `repair(id)`, `puddle`, `getState/setState`, `level`. |

## Rules of the code

- `onUpdate` is wrapped: one error switches the mod off, puts everything back and logs once (`carSurfaceFx.resume()` retries).
- Material reloads only on state changes, one per frame at most. Nothing allocated per frame.
- Tests before each commit: `node tools/luatest.js` (rules, smoke test against a mocked game, scratch memory), `node tests/simtest.js`, `node tests/scratchjs_test.js`, `node tests/paintwater_test.js`, `node tools/globalcheck.js` (undefined globals; needs `luaparse`; the tests need `fengari`), `node tools/upvalues.js` (LuaJIT loads no function with more than 60 outer locals; fengari does not notice).

## What was found (so nobody tries it again)

- Vehicle materials are shared by name; a clone made from Lua and switched on per car renders chrome (the hidden per-car paint state does not reach it). Edit the original in place.
- `flush` alone does not apply a material edit; `reload` does (~20-35 ms).
- Layer animation (`animFlags`, `scrollDir`) moves every map of the layer, not just a detail map, and Wave/Sequence share the matrix: not usable on paint or glass with maps.
- The engine puts the material's folder in front of a `@tag` in normal, detail and opacity slots (load fails); baseColorMap, colorPaletteMap, emissiveMap (and the metallic and roughness slots the stock dynamic decals use) resolve it.
- imgui is switched off in a play session: no screen-space overlay with it.
- The inner windscreen pane of the vivace ignores both the emissive and the colour slot; the outer pane is drawn double sided while wet instead (testing).
- The game reports the Material class as `material` (lower case).
- `getSwitchableMaterial(orgMat, offMat, mesh)`: the third argument is the slot's off state; the first is the mapTo, not the Material name.
