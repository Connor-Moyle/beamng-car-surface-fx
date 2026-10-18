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
