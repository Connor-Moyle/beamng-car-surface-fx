# Panel damage decals (design, texture only)

Status: design for review. Nothing is built. Scope (Connor): the look of a hit on a body panel, drawn as a texture. No physics change, no mesh change. Dents on metal (soft taps and big hits), cracks and snaps on plastic, cracks on fibreglass, splits on carbon, chosen by the panel's material. Off by default, one master switch and one switch per kind.

## 1. What is possible (checked in the game's files and in our own code)

| Way of drawing | What it can do | Verdict |
|---|---|---|
| **A. The paint canvas we already own** (`scratch.lua`: two live web canvases per car, `@csfx_base` and `@csfx_palette`, bound to the car's own paint layer; marks are drawn in their real colour and erased from the palette) | Anything drawn in 2D at a UV position: radial shading, lines, cracks, chips. Colour and light/dark, so a dent can be drawn as a lit and a shaded crescent (a fake normal). It follows the car (a texture), costs one canvas draw per hit, is per vehicle, and is put back exactly on the way out. | **Use this.** It is proven (scratches and dirt splats run on it) and the node to UV lookup (`meshuv`, `car.lut[nodeId] = { u, v, ... , texture units per metre }`) already gives the hit position and the texture scale. |
| B. `Engine.Render.DynamicDecalMgr.addDecals` (the immediate projector the ground marks use) | A box projected onto whatever the depth buffer shows, with a colour texture. It is drawn for one frame, so a decal on a moving car must be re-added every frame with the car's transform: N decals for the life of the car. No normal slot for us (the shader `deferred_decalP.hlsl` takes a colour). | Not for permanent damage. Possible only for a short flash. |
| C. The 0.40 dynamic decals editor API (`lua/ge/extensions/editor/api/dynamicDecals.lua`, 3081 lines; layer stack with a decal normal texture and normal intensity) | A real decal layer system with normals. But it is the livery editor: it bakes layers into skin textures on disk (`*_d.data.png`) and swaps materials (`setVehicleMaterialJob`). Baking per hit is far too slow and it replaces the car's skin. | Not for live hits. Maybe later for a "repair shop re-bake". |
| D. A real normal map per hit | Our earlier finding stands: the paint layer's normal slot cannot take a canvas, and a file texture cannot be placed per hit. | Not possible. |

So: **dents are drawn as shading in the colour canvas (A)**. The honest limit is that a dent is a painted light and dark pair, not a changed normal, so it reads well from the side-on light of a street and flatter in a straight-on light. Cracks, splits and chips are marks and look right.

Limits inherited from `scratch.lua` (same canvas, same rules):
- A paint layer whose palette map is a real texture (a livery, a car with colour zones such as the ETK 800) can only be darkened, so there a dent is drawn only as its dark half and a chip as a dark mark. The code asks the scratch module which mode the car is in.
- A car with no source `.dae` has no UV map and gets nothing.
- Cars sharing a material all need the canvases (already handled by scratch).

## 2. The hit: where and how hard

Reuse, do not add a second contact hook. `carSurfaceFxContact` (vehicle side) already publishes every node collision `{ node, mat1, mat2, perp, slip, normalForce, x, y, z, nx, ny, nz }` and beam break `{ beam, energy }`, and `carSurfaceFxImpacts` already filters them (thresholds, per-node cooldown, clusters of nearby hits `clusterRadius 0.8 m`).

- **Where:** the colliding node id (`ev.node`) is the hit point; its UV and the texture scale come from the same `lut` the scratch marks use. A hit between nodes (a beam break) uses the beam's first node.
- **How hard:** an energy estimate in joules from the contact: `E = 0.5 * m_eff * perp^2` with `m_eff` = the car's mass divided by its node count times a small factor for the nodes around (the hit spreads over neighbours), and a floor from `normalForce * 0.002 m` (a force over a small give). Used only to pick the size and depth of the mark and to apply thresholds, so it does not need to be exact. A first calibration: a tap 1 to 2 m/s is a light dent, 4 to 6 m/s a deep one, above that a crease. The probe in section 7 measures real values.
- **One per spot:** nearby hits within `clusterRadius` merge into one mark that grows (deeper and bigger up to a cap), so a long scrape or a rattle of contacts is not a hundred stamps.
- **Budget:** a short per-car cooldown (0.3 s), at most 40 marks per car (the oldest merge into a "scuffed" mark), a stamp is one canvas draw like a scratch (about the cost of the existing scratch hit).

## 3. The panel's material

Order of the checks (first answer wins), with a lookup table kept in one data file (`art/surfacefx/panels/materials.json`, user-editable) and a fallback to metal:

1. **Material name of the mesh the node belongs to** (the car's material names are available per flexbody: `veh:getMaterialNames()`; the node to mesh link comes from `meshuv`): contains `carbon` then carbon; `fiberglass`, `fibreglass`, `glassfibre` or `frp` then fibreglass; `plastic`, `bumper`, `cladding` then plastic.
2. **Jbeam part and slot name of the node's flexbody** (`v.data.flexbodies[i].mesh` / the part name): a table of patterns, for example `bumper*`, `fender_flare*`, `mirror*`, `grille*`, `spoiler*` (plastic, except cars whose table says otherwise), `*_carbon*`, `hood_carbon`, `roof_carbon` (carbon), and per-car overrides for fibreglass bodies (the table lists the vehicle folder and the parts).
3. **The node material** the jbeam gives (`nodeMaterial`: METAL 2, PLASTIC 3, GLASS 5 is the windows, which CSFX already handles, RUBBER 4 is ignored): PLASTIC then plastic, METAL then metal.
4. **Fallback:** metal.

The table is the part that needs the real cars: the first version lists the 30 stock cars by checking their parts once with a script (`tools/list_panel_parts.py` reads the jbeam and prints part, slot, mesh, material so the table is filled from facts, not guesses).

## 4. What each kind looks like (the stamp)

All are drawn in the canvas at the node's UV, sized by `energy` and the texture scale (centimetres to texture units), in the same call style as `csfxLines`.

| Kind | Soft hit | Hard hit |
|---|---|---|
| **Metal** | a shallow dent: a soft dark ellipse with a lit crescent on the light side and a darker crescent opposite (about 5 to 15 cm) | a deep dent or crease: elongated along the slip direction, sharper edge, paint chipped to bare metal along the edge (the scratch colour), a few short scratches |
| **Plastic** | a scuff and a faint stress-white patch | cracks: a star of 3 to 6 thin dark lines with white stress edges; a snap: a clean split line across the panel width with a gap shadow |
| **Fibreglass** | star cracks, white at the edge fading into the gel coat | a crazed area: many fine cracks, a small chipped hole shown dark |
| **Carbon** | a few fraying lines along the weave direction | a split: a ragged slit along the weave with a lighter fibre edge and a dark core |

The shapes are drawn procedurally in the JS next to `scratch.html` (radial gradients and line sets with a seeded random per hit, so a hit looks the same after a replay), with optional **texture stamps** (section 5) for the crack patterns. Colour follows the paint where the canvas allows (a dent is a shade of the paint colour, found from the paint lum the scratch module already keeps in `setPaintLum`).

## 5. Texture sources

Procedural first, photographs only where a pattern cannot be drawn well:

- **Dent shading, scuffs, edge chips:** our own, generated by `tools/make_damage_textures.py` (radial and elliptical height profiles turned into lit and shaded stamps at 3 light directions, 6 to 8 variants per size; no third-party asset).
- **Crack and split patterns** (plastic, fibreglass, carbon): 5 to 10 per kind as small alpha stamps (256 px). Made procedurally (Voronoi and random-walk crack lines) and, where that looks fake, derived from CC0 photographs of cracked paint, plastic and carbon from **ambientCG** (CC0 1.0). The exact asset ids are chosen and recorded in `docs/TEXTURE_CREDITS.md` before any of them is used; none is picked in this design. Photographs are never shipped; only the derived alpha stamps are, as the dirt splats already are.
- Texture rules of the BeamNG repository apply when they ship (name by type, cooked DDS from the build step).
- 0.40 note (from ba): a PNG used by an engine material that is new or changed is cooked to /temp on first use, and the reload that follows blanks any material switched in at spawn. Panel damage uses no engine material: the dents and the crack stamps are drawn in the paint canvas by a web page, and the stamp atlases are loaded there as images (like the splat atlases), so they are not affected. If a kind ever needs an engine material (a detail normal), it ships as pre-cooked DDS with mips and the material still names the .png.

## 6. Settings, API and the tyre blowout

Settings (Mods menu, new page **Panel damage**, tags for the Active features tab):
- master `paneldamage.enabled` (default **off**);
- per kind: `metal`, `plastic`, `fibreglass`, `carbon` (each a bool, default on once the master is on);
- amount (0.5 to 2: size and strength), minimum hit energy (so parking taps are ignored), "also on other cars" (like the other modules), and the maximum number of marks per car.

Module: `carSurfaceFx_paneldamage` (GE), loaded and gated like the other CSFX modules; saved with the car's scratch memory (`scratch.getState/restore`) so marks survive a respawn; `repair(id)` clears them (the existing repair hook), and the car wash does not.

API (the one ba asked for), usable from the tyre blowout and from anything else:

```lua
-- a hit on car vehId at a world position, with its energy in joules. kind is optional ('metal'|'plastic'|'fibreglass'|'carbon'); nil = chosen from the panel under that spot.
-- dir is an optional world direction (the slip direction, for creases). Returns true when a mark was drawn.
carSurfaceFx_paneldamage.damageAt(vehId, worldPos, energyJ, kind, dir)
carSurfaceFx_paneldamage.damageNode(vehId, nodeId, energyJ, kind, dir)   -- when the node is known (the contact path uses this)
carSurfaceFx_paneldamage.clear(vehId)
```

`damageAt` finds the nearest node (the scratch map's `lut` is by node, so it takes the closest node to the position, within 0.4 m, else returns false). The tyre blowout calls `damageAt` for each panel it pushes (position of the panel node, energy from its force times the step). With the master off the call returns false and costs nothing.

## 7. Feasibility probes for 80 (before any building)

Each is one console command on a normal car on West Coast USA; a screenshot and a number back.
1. **Dent look:** stamp a test dent at a door node (`carSurfaceFx_paneldamage.probe('dent', 1)`): is the light and dark pair readable in sun, in the shade and at night? Take it side-on and head-on.
2. **Darken-only cars:** the same on a car with a palette texture (ETK 800) and one with a livery: does the fallback read as a dent?
3. **Position accuracy:** stamp at 10 nodes along a door and a bumper: does each land on the right panel, near seams and on a curved fender?
4. **Real energies:** log `perp` and `normalForce` for a parking tap, a kerb hit, a wall at 20, 50 and 100 km/h: the numbers set the energy thresholds.
5. **Cost:** 40 marks on one car and on 4 cars: frame time (the budget is the scratch module's, about 1 ms while drawing).
6. **Plastic and carbon:** the parts table is filled from the script; check one bumper, one carbon hood on a car that has them.

## 8. Build plan (after the design is accepted)

1. The data: `tools/list_panel_parts.py`, the materials table, `tools/make_damage_textures.py`, the credits file.
2. The pure rules (energy, kind choice, thresholds, merging, the table lookup) in `carSurfaceFx/panelrules.lua` with a unit test (no game).
3. The stamps in `scratch.html/js` and the GE module `paneldamage.lua` with `damageAt/damageNode/clear/probe`; the vehicle side subscribes through `carSurfaceFxContact` (one more subscriber, same cooldown rules).
4. The Mods page, master and per-kind switches (default off), tests for every row (every value read, every switch tagged).
5. A 80 game check with screenshots per kind.
