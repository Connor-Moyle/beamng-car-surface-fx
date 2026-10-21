# Terrain deformation probe: dropped (ba, 2026-10-23)

The research (Graph TERRAIN_DEFORM_RESEARCH) listed eight probe steps to find out whether wheels could really sink the ground (writing the terrain's height data at runtime). Decision: the probe is dropped, not finished.

Why:
- Writing terrain data at runtime is the same class of operation as the terrain texture swap that is part of the wet-world High crashes: it repacks the terrain cache on the GPU. A first test of it would be a test on Connor's GPU with a known device-loss class around it, for a result the game's own physics cannot use anyway (the physical ground stays as it is; a deformed render would not match what the wheels touch).
- The visual route exists and is built: terrain hollows (the drawn ground sinks a little under the wheels, looks only) plus ruts, soil banks, lit tracks and gouges. None of them has been seen in the game yet, so a deeper route has nothing to be compared against.
- The level-end rule (never write terrain while a level ends) already makes terrain writes the riskiest code in the mod.

What would change the decision: hollows are seen working and judged too shallow to read, and the wet-world work shows terrain writes are safe at High.
