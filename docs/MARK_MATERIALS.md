# Ground mark materials (lit decal road route)

Procedural PBR texture sets and materials for the marks that go the DecalRoad route (docs/DECALS_RESEARCH.md): lit by the scene, shadowed, glossy where wet. All made by our own
script, `tools/make_mark_textures.py` (numpy and PIL, no third-party assets); `tools/check_marks.py` checks them; `tools/preview_marks.py` renders a lit contact sheet
(`docs/marks_preview.png`: each type in sun, in shade and wet). Everything is under `mod/art/surfacefx/marks/`: one folder per type, `main.materials.json`, `marks_index.json`.

## The set

| type | for | image (across x along) | road width / texture length | maps |
|---|---|---|---|---|
| `skid_asphalt` | a tyre's rubber skid on tarmac | 128 x 512 | 0.35 m / 4 m | colour, opacity, normal, roughness |
| `track_dirt`, `track_gravel`, `track_sand`, `track_mud`, `track_snow` | a tyre track with tread pressed into the surface | 256 x 512 | 0.5 m / 3 m | + ambient occlusion |
| `rut_dirt`, `rut_gravel`, `rut_sand`, `rut_mud`, `rut_snow` | a deep wheel rut with raised lips | 256 x 512 | 0.9 m / 4 m | + ambient occlusion |
| `gouge_asphalt`, `gouge_dirt` | a ground gouge (body scrape on the ground) | 128 x 512 | 0.45 m / 3 m | + ambient occlusion |
| `wall_concrete`, `wall_metal` | the streak a wall or barrier scrape leaves | 128 x 512 | 0.5 m / 3 m | colour, opacity, normal, roughness |
| `oil`, `coolant`, `fuel` | a fluid stain, one blob | 256 x 256 | 1 m x 1 m (any size, it is one blob) | + a dry roughness map |
| `test_bump` | TEST: domes left, pits right, to see which way the normals are read | 256 x 512 | 1 m / 4 m | |

Size on screen is set by the road: width in the nodes, `textureLength` per texture repeat. 19 types, 38 materials; 5 MB of png, about 7.6 MB in the video memory once compressed
with mips (colour BC1, normal BC5, the greys BC4).

## The materials

Each type has two: `csfx_<type>_dry` and `csfx_<type>_wet`, in the game's own format (version 1.5, `translucent`, `translucentZWrite`, `materialTag0` RoadAndPath, as the base
game's `m_dirt_tiretracks`). Texture names follow the game's: `t_<type>_b.color.png`, `_o.data.png` (opacity), `_nm.normal.png`, `_r.data.png` (roughness), `_ao.data.png`.
- Strips and the other types: wet is the same textures with `baseColorFactor` 0.8 (darker) and `roughnessFactor` 0.4 (glossier), and `opacityFactor` 1.0 (dry 0.95).
- Fluids: wet uses the glossy roughness map (`_r`, 0.05 to 0.1: a mirror-like film), dry the matte one (`_r_dry`, 0.45 to 0.8, a tacky stain), and dry has a lower opacity factor (0.7) and a lighter colour factor (a dried residue).
Use: pick `_wet` while the ground is wet (the `wet` value above about 0.3, with a little hysteresis so it does not flip), `_dry` otherwise. A fluid stain starts `_wet` and is moved to
`_dry` after its drying time. Changing the material of a road is a one-line `setField('material', ...)` on the road object.

`carSurfaceFx/markMaterials.lua` makes sure the materials exist: `ensure(name)` builds one from `main.materials.json` with `createObject('Material')` if the game did not load it
(the game may not scan a mod's `art` folder for material files), `ensureAll()` does all, `index()` returns the type list with width, texture length and the two names. Call
`ensure` before a road uses a material.

## How the images are laid out

U across the road, V along it. Strips fade to nothing at their left and right edges and tile along V (checked: the step from the last row to the first is no bigger than an ordinary
step). Stains fade to nothing before the edge. **Assumption to verify:** that a decal road puts the image's long side along the road (the game's own tyre track and crack textures
tile along the road); `test_bump` and any strip show it at once. If it is the other way, the images need turning by 90 degrees (a flag in the script).

**Normal maps are written in the DirectX convention (green down)**, as the engine's other normal maps are believed to be; the swatch map shows if that is wrong (`test_bump`:
with the sun on one side, a dome is bright on the sun side and a pit dark on it; if they look the other way round, run `python tools/make_mark_textures.py --flip-green` and
`python tools/check_marks.py`). The roughness factor is assumed to multiply the roughness map (the game's own materials carry both); if it does not, the wet strips need
their own maps (the fluids already have).

## What each looks like (docs/marks_preview.png)

- Skids: near-black rubber, streaked along the road, ragged soft edges, slightly smoother in the middle. Faint on dark tarmac by nature.
- Tracks: a darker pressed band with a chevron tread, a fine grain; gravel has stones, sand a soft shallow print, mud is deep and glossy in the groove, snow compressed and bluish.
- Ruts: groove and raised lips from the normal map (the carrier), ambient occlusion darkens the groove, colour darker and moister in the middle; mud and snow glossier in the groove.
- Gouges: a light scar (bare asphalt or soil) with dark edges, chipped, a groove with raised chips in the normal map.
- Wall scrapes: concrete a pale dust smear with thin dark scratch lines; metal a dark paint streak with thin bright scratches (low roughness in the scratches).
- Stains: oil near-black with a faint tint at the rim; coolant green and translucent; fuel nearly clear with a faint rainbow ring. Wet is glossy (the sky reflects in it), dry matte.

## Test map for connor-80 (sun, shade, rain)

`carSurfaceFx_markSwatches` (not loaded by the mod): `extensions.load('carSurfaceFx_markSwatches'); carSurfaceFx_markSwatches.run()` lays all types ahead of the car on the ground in three
blocks of rows, dry on the left and wet on the right of each pair, with a label for each type (`run('rut')` only the types with that in the name; `clear()` removes it all).
Steps (install the branch worker-a-marks as the mod):
1. `test_bump` first, in sun with the car's shadow off it: domes bright on the sun side and pits dark on it? If not, tell me, and I flip the normals.
2. Does every strip lie along the road with its long side (no sideways stretched images)? Do they tile without a seam (look along a strip)?
3. Shots from behind the car for the whole map in: noon sun, late afternoon (long shadows), shade (a bridge or tree), dusk, night with the headlights on, and in rain (set the weather; the map stays). Low and high camera.
4. Is wet really darker and glossier than dry (the pairs)? Do the fluids' wet stains reflect the sky?
5. Do the ruts read as grooves with lips; the tracks as pressed treads; the gouges and wall scrapes as scars?
6. Errors in the log (material fields, `insertNode`), and the frame time with the whole map in view against without (`clear()`).
7. Put shots in wc\morning\ as marks_*.jpg with a line each in INDEX.md.

## Open (needs a game run)

- Road V/U orientation and the normal convention (above); `roughnessFactor` multiplying; `translucentZWrite` roads overlapping at a crossing (renderPriority per type if they fight);
  whether the roads follow terrain and tarmac on every map (`overObjects`).
- Whether the base game's own decal materials are loaded outside the levels that use them (`carSurfaceFx_decalProbe.info`), which does not matter for ours.
