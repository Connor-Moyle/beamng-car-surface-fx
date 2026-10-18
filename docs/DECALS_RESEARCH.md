# Ground decals: lighting, wetness, cost (R1, R2, R4)

Read from the game's own Lua and shaders (BeamNG 0.39, `I:\SteamLibrary\steamapps\common\BeamNG.drive`) and its art archives. What is verified from files is said so; what only a game run can settle is marked **TEST** with a step in section 6.

## 1. R1: what the decal manager does

`Engine.Render.DynamicDecalMgr.addDecals(pool, count)` is an immediate-mode projector: the pool is drawn that frame only, so it is added again every frame (`core/groundMarkers.lua`, `gameplay/markerInteraction.lua`, and the old mod's `renderSkid`). An entry has exactly these fields (`groundMarkers.lua getNewData`): `texture` (a png path), `position`, `forwardVec`, `scale` (x width, y length, z depth of the box), `color` (a ColorF), `fadeStart`, `fadeEnd` (distance fade). **There is no material, normal map, roughness or metallic field.**

The shader that matches those fields is `shaders/common/deferred_decalP.hlsl`: it draws a box per decal, rebuilds the world position of each pixel from the depth buffer, projects it into the box, and returns `tex2D(diffuseMap, uv) * instanceColor` as a single colour. It reads one texture (diffuse) and one colour, writes one target, and never touches a normal, roughness or light. So a decal-manager decal is a **colour sticker**: its look is `texture x colour`, nothing else can be given to it. (**TEST A** settles whether the scene's light is applied to it afterwards: the code that sets the blend state and target is in the engine, not in the files.) The `shaders/common/dynamicDecals/*` shaders are the livery (vehicle paint decal) system, a different thing with compute baking onto meshes; not for ground marks.

Whatever TEST A says, decal-manager decals cannot take a normal map or a roughness, and have no shadow of their own.

### The route that is lit: DecalRoad with a real material

The game lays its own dirt tyre tracks, cracks, stains and road paint as `DecalRoad` objects with a normal PBR `Material` (version 1.5): `art/shapes/common/decalroads/main.materials.json`, 40 of them, for example `m_dirt_tiretracks`:

- Stage 0: `baseColorMap`, `baseColorFactor`, `normalMap`, `roughnessMap`, `ambientOcclusionMap`, `opacityMap`, `opacityFactor`, `detailNormalMap` with `detailScale`, plus `metallicFactor`, `roughnessFactor` in other materials of that file.
- `translucent: true`, `translucentZWrite: true`, `materialTag0: "RoadAndPath"`, `annotation`.

That goes through the normal material pipeline: scene sun and sky light, shadows from the scene, specular from roughness, the normal map, AO. It is how the base game gets lit ruts and tracks.

A DecalRoad can be made from Lua at run time (the editor does it with these calls, `editor/api/roadRiver.lua`, `editor/tech/roadArchitect/decals.lua`): `createObject('DecalRoad')`, `setField('improvedSpline', 0, 'true')`, `setField('material', 0, name)`, `setField('overObjects', 0, 'true')` (on maps without terrain), `setField('renderPriority', 0, n)`, `setField('textureLength', 0, metres)`, `setField('startEndFade', 0, 'a b')`, `registerObject('')`, `scenetree.MissionGroup:add(road)`, then `road:insertNode(pos, width, index)`, `road:setNodePosition/setNodeWidth`, `road:deleteNode`, `road:deleteObject()`. The material can be a mod's own (`art/surfacefx/materials.json`, like the game's). The editor calls these outside the editor's own state, but whether they behave in a plain freeroam run is **TEST B**.

Cost of that route: each DecalRoad is a scene object with its own mesh that is rebuilt when its nodes change. So: one DecalRoad per finished stretch of a mark (about 8 to 12 m, 6 to 10 nodes), made when the stretch is complete, never extended every frame, recycled oldest first, a few hundred alive at most. Fine for ruts, skids, scrapes and drips (a mark is made once); not for something that grows per frame.

## 2. Recommendation

1. **Ruts, tyre tracks on loose ground, skid marks, ground scrapes, fluid stains: DecalRoad with our own PBR material per mark type** (section 4). Lit, shadowed and glossy where it should be, for the price of finishing stretches before drawing them.
2. **Decal manager only where a plain tinted sticker is right** (faint constant tracks, many tiny marks), and give it the light itself: a per-mark colour multiplier from the scene (section 3). TEST A may show it already is lit; then nothing is needed.
3. Debris, glass shards, sparks are not decals: real shapes (`TSStatic`/meshes) are lit by the engine; the old mod's `debugDrawer` billboards are not and will look flat. Glass piles: DecalRoad with the glint material in section 4.

## 3. Lighting a decal-manager decal ourselves (cheap, approximate)

Colour is the only input, so multiply it by what the light would do: `colour x sunFactor x shadowFactor + ambient`.
- Time of day and sky: `core_environment.getTimeOfDay()` (sun angle) gives day, dusk and night; ambient from the sky brightness. At night with headlights on the car lights the ground; the decal manager would not, so night marks need a floor (a minimum brightness near the car).
- Shade: one `castRayStatic` from the mark towards the sun when it is made and every few seconds for visible marks (static scene only: buildings, trees, bridges; the car's own shadow is not in it).
- Wet: section 5.

It never gets the normal map's light response; a rut baked with fake shading in the texture (what the old mod did) stays flat at noon and wrong at dusk.

## 4. Material and texture recipe per mark type (DecalRoad route)

All textures: white-on-transparent or colour, 256 to 512 px, tileable along their length, 8-bit png, `.color.png` / `.normal.png` / `.data.png` naming as the game's (the engine treats the suffix as the colour space). `translucent: true`, `translucentZWrite: true`, `materialTag0: 'RoadAndPath'`, `castShadows: false`. Width in the road nodes; `textureLength` 2 to 4 m. Strength numbers are starting points.

| Mark | baseColor | opacity map | normal map | roughness | AO | Wet (section 5) |
|---|---|---|---|---|---|---|
| Skid, tarmac | near-black rubber (0.03 to 0.06), fine grain | streak, soft ragged edges, lighter at the ends | almost flat: a fine tread ridge, strength 0.2 | 0.55 (rubber, a little smoother than asphalt) | none | roughness down to 0.2, colour a little darker |
| Skid or track, dirt, gravel, sand | the surface colour x 0.55 (compressed, darker) | soft with ragged edge | tread grooves pressed in, strength 0.6 to 1.0 | 0.9 dry | dark in the grooves | darker, roughness 0.35 on mud |
| Rut | surface colour x 0.5, wet-looking centre | lips fade out | **the carrier**: a depression, centre low, raised lips on both sides, strength 1.0; plus a `detailNormalMap` for break-up (`detailScale` [2,4] as the game's) | 0.85 | dark in the groove | puddle look: roughness 0.1 in the groove only (roughness map) |
| Oil | very dark (0.02), a hint of blue-brown | irregular blob, soft edge, radial | flat, a thin raised rim | **0.08 to 0.12**, glossy | none | no change (already glossy) |
| Coolant | tinted (green or orange, 0.2 to 0.4), partly clear | blob | flat | 0.05 | none | a puddle on wet ground merges: skip |
| Fuel | near clear, faint rainbow tint | blob, thin | flat | 0.06 | none | skip |
| Ground scrape / gouge (terrain scratch) | lighter bare soil or concrete, dark edges | line with chipped edge | a groove with raised chips, strength 0.8 | 0.8 | dark along the groove | darker |
| Glass shards | near clear, faint blue-white, low alpha | scattered shards | **facet normals**, strength 1.0, random facet angles | 0.04 | none | n/a |

Shadow and light come from the pipeline; none of this needs lighting maths of our own. Specular on the fluids comes from the sky and the sun reflecting off roughness 0.1: that is what makes a puddle of oil read as wet and lit.

## 5. R2: wetness

The shaders have no global rain wetness (grep over `shaders/` finds `wetness` only in the water and underwater code). Roads and decals do not get wet by themselves; the `wet` value we already have (the rain's wetness, 0..1) has to do it.

- **DecalRoad materials:** change the material, as the paint rungs already do: a wet rung per material (`roughnessFactor` down, `baseColorFactor` darker, `opacityFactor` up a little), one `reload()` when the rung changes. The material is shared by all marks of that type, so it costs one reload per type per rung change, not per mark. Use two or three rungs (dry, damp, wet).
- **Decal manager:** the colour: `colour x (1 - 0.35 x wet)` per frame at no cost; it cannot get glossier.
- **Standing water in ruts:** a second decal layer (a puddle material, roughness 0.05, opacity from a map that fills the groove) whose `opacityFactor` follows `wet` x the rut's depth; or the rut material's roughness map gives the groove 0.1 when wet (above).

## 6. Game steps (for connor-80)

Probe: `carSurfaceFx/decalProbe.lua`, on branch `worker-a-decals`. It is loaded from the console, creates nothing until asked, and removes everything it made on `clear()`.

**TEST A (does the decal manager light its decals?)**
1. `extensions.load('carSurfaceFx_decalProbe'); carSurfaceFx_decalProbe.run()` on a flat road. Left: 4 white strips by the decal manager. Right: 4 white strips as DecalRoads with the game's plain white material `BlankWhite` (a normal lit material).
2. Screenshots from behind the car, same camera, for: noon sun; late afternoon (the car's shadow across a strip, or a bridge or building shade: `core_environment.setTimeOfDay` or the time slider); dusk; night with the headlights off and then on; rain (`core_environment.setPrecipitation`).
3. Report what each row's brightness does. **If the left row stays equally white in shade and at night while the right row darkens, the decal manager does not light its decals** and the DecalRoad route is needed. If both follow the light, the decal manager is lit too and the recipe in section 3 is unnecessary.

**TEST B (a lit DecalRoad made at run time, with the game's own tracks)**
1. `carSurfaceFx_decalProbe.info('m_dirt_tiretracks')` and the same for `m_asphalt_cracks_02`: is the material loaded, with its maps? (Not loaded: tell me which level it needed.)
2. `carSurfaceFx_decalProbe.road('m_dirt_tiretracks')` on dirt and on tarmac: a 14 m strip ahead of the car. Screenshots in sun, shade, rain; does it lie on the ground (terrain and roads), show the normal map, take shadows?
3. Report errors in beamng.log (`insertNode`, `setField`), and whether `carSurfaceFx_decalProbe.clear()` removes it all.

**TEST C (frame cost of many decals):** compare the frame time with 0, 1000, 3000 and 6000 decal-manager decals drawn in view (a pool of that many entries re-added each frame); `slrr_perfProbe` (WW branch worker-a-perf) can time `onPreRender`. Report ms.

## 7. R4: the old ring buffers

The old counts: skid 2000, track 3000, drips 800, wall 600, ruts 2500, glass 400: 9300 marks.

- **Lua side** (the old per-frame loop: walk every mark, cull by distance to the camera, write position, forward vector, scale and colour into pool entries, one `addDecals` per surface batch): measured in LuaJIT with plain tables and `set` method calls: **0.27 ms per frame** at 160 m (4600 of 9300 drawn), 0.15 at 100 m, 0.11 at 60 m. With real engine `vec3` userdata the three `set` calls per drawn mark cost more: about 0.4 us each, so about **2 ms at 4600 drawn** (estimate, not measured). Memory: about 150 B a mark, 1.4 MB: nothing.
- **GPU side:** unknown offline. Each decal is a box drawn over its footprint with a depth read; the cost is the pixels covered times the overlap, and constant tracks overlap heavily. **TEST C.**
- **Advice:** draw distance 100 m for skids and tracks (160 m is far: a mark that small is invisible), 60 to 80 m for drips and scrapes, 160 m only for ruts if they read; a grid cell index (or a visible list recomputed at 10 Hz and when the camera has moved 10 m) in place of walking all 9300 marks each frame; pool entries made once; one `addDecals` per surface texture (a batch can only carry one texture, as the old code noted); and a cap of about 800 decals drawn per frame whatever the distance, nearest first. The `fadeStart`/`fadeEnd` per entry already fades by distance in the engine; set them to 80% and 100% of the draw distance.
- DecalRoad route: count roads, not marks: 200 to 400 alive covers a few hundred metres of marks at 10 m a road; each is a mesh the engine draws every frame (cheap) and rebuilds only when made.

## 8. Open questions (need a game run)

- TEST A: lit or not, the decal manager.
- TEST B: DecalRoad from plain Lua in freeroam, and whether the game's decal materials are loaded outside the levels that use them (else ship copies in `art/surfacefx/`).
- Overlap and sorting of many `translucentZWrite` roads on one spot (`renderPriority` per type).
- Whether a material reload for a wet rung hitches with hundreds of roads using it.
