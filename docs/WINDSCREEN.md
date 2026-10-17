# Windscreen drops (design, offline)

Goal: drops on the glass in the cockpit/hood camera, blown by speed, merged into runs, cleared by the wipers; nothing per frame allocated; < 0.3 ms.

## Options checked (0.39)
| Option | Verdict |
|---|---|
| Edit the glass material (vivace_glass etc.) with a bead normal map, like the paint | Static beads only, no motion, no wiper clearing. Cheap fallback. |
| Particles on the glass nodes | Cannot sit on a moving flat surface cheaply; rejected. |
| **imgui draw list in the GE** (`ui_imgui`: GetBackgroundDrawList1, ImDrawList_AddCircleFilled, AddImage exist in lua/common) | **Chosen.** Pure 2D overlay drawn in GE `onPreRender`; a drop = a few translucent circles + a highlight. Not part of the 3D scene, so it ignores the real glass shape (acceptable: a fake lens). |
| CEF/UI app canvas | Heavier, async; only if imgui cannot draw in the game HUD (editor-only so far: the only users in lua/ge are editor files, so this is UNVERIFIED in a normal game session). |

## Model (pure Lua, testable like rules.lua)
Fixed pool of 150 drops {x,y (0..1 screen), r, vx, vy, age}. Spawn rate = rain intensity (the same wetness) x speed factor. Per update: gravity pulls down, speed pushes drops up/outward (stronger when fast), a drop with r above a threshold slides and leaves nothing (no trails: cheap), two overlapping drops merge (r = sqrt(r1^2+r2^2)). Wiper sweep clears drops in its arc.
Draw only when the active camera is a driver/onboard/hood one (`core_camera.getActiveCamName()`: 'driver', 'onboard' ...), not in chase/orbit, and the car is the player's.

## Wipers
Vivace/ETK wipers are jbeam parts; the state is somewhere in `electrics.values` (probe below). If none exists, the wipers switch is left unmodelled and drops clear by timer (a single parameter), documented.

## Steps for the game (manager)
1. Probe imgui drawing in a normal session: run_lua
   `local im=ui_imgui; local dl=im.GetBackgroundDrawList1(); im.ImDrawList_AddCircleFilled(dl, im.ImVec2(400,300), 40, im.GetColorU322(im.ImVec4(1,1,1,0.5)), 24) return 'ok'` -- only visible for one frame; for a real test it needs to run in onPreRender (I add a debug call `carSurfaceFx.windscreenTest()` for it).
2. Probe wipers: vehicle Lua `local o={} for k,v in pairs(electrics.values) do if tostring(k):lower():find('wiper') then o[#o+1]=k..'='..tostring(v) end end return table.concat(o,' ')` with the wipers switched on and off.
3. Cockpit camera name: `core_camera.getActiveCamName()` in driver view.

## Build order after the probes
rules (pool step, merge, wiper clear + tests) -> overlay module -> setting `windscreen.enabled` (default off until tested) -> debug('rain', x) already drives it.
