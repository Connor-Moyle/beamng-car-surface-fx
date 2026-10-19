# Tyre simulation: step 1, the probes

Question each probe answers (docs/TYRE_WEAR_RESEARCH.md, section 9.2). Offline prep; **nothing is merged into a mod until these have run.**
Run on the player's car in a level (a flat road or a skidpad), through the MCP tool `run_lua_vehicle` (vehicle Lua of the player car). A vehicle reset undoes everything; each writing probe also has a restore.

1. Load: send the whole file `tools/probes/tyre_probes.lua` as the code. It defines `CSFXP` and returns it.
2. Each step below is one call: `return CSFXP.<fn>(<args>)`. Every result is text; `ERR:` lines are answers (the API differs from the research).
   Save all the text and send it back, with a screenshot where noted.

| # | Call | What to do | What it tells us |
|---|---|---|---|
| 0 | `CSFXP.info()` and `CSFXP.api()` | nothing | wheels, tread node counts (16 or 20 rays: 32 or 40), base friction, which bindings exist (`setNodeMaterial`, `getNodeFrictionCoef`, `setThermal`, ...) |
| a | `CSFXP.friction(0)` | then drive and handbrake-turn; the corner with half grip should slide; `CSFXP.frictionRestore()` | per-node friction set and read back work, and the grip really changes |
| b | `CSFXP.collisionStart()` then drive 20 s with a burnout and a locked-wheel skid, then `CSFXP.collisionRead()` | | calls per second for `nodeCollision`, how many distinct nodes, the fields (`slipVel`, `slipForce`, `normalForce`, material ids). If 0 calls: the engine does not go through `wheels.nodeCollision`, we need a controller instead |
| c | `CSFXP.materials()` then `CSFXP.switchWheelMaterial(0, 'tire_01a_old')` and a screenshot, then `CSFXP.switchWheelMaterial(1, ...)`, then `CSFXP.resetMaterials()` | | whether FL and FR share a mesh, and whether ONE tyre can change alone (the shared-mesh risk) |
| d | `CSFXP.sparks(2)` (a rear wheel), then a burnout on asphalt and a screenshot, then `CSFXP.sparksRestore(2)` | | whether METAL tread nodes spark and sound like metal |
| e | `CSFXP.thermal(2)` then a 10 s burnout, then `CSFXP.thermalRead(2)` every few seconds | | whether the native thermal can be turned on at runtime and what it reads (units), and whether `setFrictionThermalSensitivity` changes grip (compare a skid with and without) |

Wheel indices are the keys of `wheels.wheels` (`info()` lists them). Stop and report if the car pops a tyre or the game stutters.

## Fire, smoke and rubber debris (added 2026-10-19)

Game facts (`lua/vehicle/fire.lua`): the fire system only burns nodes whose jbeam has a `flashPoint`; tread nodes do not. It pops a tyre when a wheel HUB node (`node1`/`node2`) passes `tirePopTemp = 650` C. So a tyre fire is ours: flame/smoke particles on a tread node (ids 25/27/29 flames, 51/52 smoke), then `beamstate.deflateTire`.
Thresholds in `tyrerules.lua`: smoke from 150 C (full at 250), ignition when the surface holds 350 C for 2 s, a burning tyre pops after 8 s, rain douses it. Hot debris on the road (50 g or more, still above 350 C) can burn for 12 s.

| # | Call | What to do | What it tells us |
|---|---|---|---|
| f1 | `CSFXP.fireInfo()` | nothing | is the fire module there, how many flammable nodes, which calls exist |
| f2 | `CSFXP.fireParticles(2, 27, 20)`; repeat with ids 25, 29, 51, 52 and a screenshot of each | stand next to the rear wheel | the flame/smoke particle looks right on a tread node |
| f3 | `CSFXP.fireInject(2)`, watch 10 s, screenshot, then `CSFXP.fireClear()` | | can the game's own fire burn a tread node (the table is writable)? does the tyre stay un-popped? |
| f4 | `CSFXP.fireDeflate(2)`, then reset the car | | the pop call works and looks right |
| f5 | `CSFXP.debrisParticle(2, id)` for id 1..60, driving slowly, note the ids that look like rubber or dirt bits | | which particle we can use for flung rubber (otherwise CSFX adds its own) |
| f6 | `CSFXP.fireNearest(2)`, watch 20 s, then reset the car | run only if f3 fails or burns nothing | lights the car's flammable node nearest the wheel: does the game's fire spread through the wheel arch and body? |
| f7 | `CSFXP.blowout(0)` (front-left; the `0` is the wheel index from `info()`) then `CSFXP.blowoutApply(1500, 0.05)` once (a sustained push; try `-1500` if the panel is pulled inwards); screenshot the arch before and after. Repeat at 50 and 100 km/h (apply right after the pop, while moving), reset the car (R) between runs | do not exceed the cap (3000 N, 3 nodes) | do panels near the wheel deform from outward pushes, does Wrench Works see it as damage, does the car stay stable? Also say how many nodes were in range |

| f8 | `CSFXP.forceTry(0, 200)`, a second later `CSFXP.forceRead()` | a car standing still on flat ground; reset (R) afterwards | which force call exists with which arguments (`applyForce(n1, n2, F)`, `applyForceTime`, `applyForceVector`), and whether a tread node moves: the physical flat-spot shake (research 8.6, level 3) needs one that works from a frame-rate update |
| f9 | `CSFXP.pump(2, 51, 8)`, then ids 52, 25, 27, 29 (8 s each, screenshot at 2 s and 6 s from 1.5 m at the wheel; `CSFXP.unpump()` stops it) | car parked | smoke 51/52 looked right in the first run (dark rising smoke); this repeats it the way fire.lua emits, and tests whether the flame ids show up at all when called every 0.1 s |
| f10 | `CSFXP.fireStrong(2, 3)`, watch 10 s, screenshots at 3 s and 8 s, `CSFXP.fireClear()` | parked | the game's own fire on a tread node with a real burn rate: flames and smoke, does the tyre stay intact |

