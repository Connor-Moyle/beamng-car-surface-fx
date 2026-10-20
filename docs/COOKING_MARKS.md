# Shipping the ground marks as cooked DDS

BeamNG 0.40 cooks a PNG that a material names into a BC7 / BC5 DDS the first time it is used. Same rule as the tyre overlays (tools/make_tyre_stage_textures.py): ship the game's own
cooked DDS, with the materials still naming the `.png`, and delete the PNGs.

1. In the game, with a level loaded and Car Surface FX on, draw every mark material once, so the game cooks each texture (dry and wet):
   ```
   extensions.load('carSurfaceFx_decalProbe')
   local mm = require('carSurfaceFx/markMaterials') mm.ensureAll()
   for _, t in ipairs(mm.index()) do carSurfaceFx_decalProbe.road(t.dry) carSurfaceFx_decalProbe.road(t.wet) end
   ```
   Wait until the log has no more "TextureCooker" lines, then `carSurfaceFx_decalProbe.clear()`. (The berm materials share the rut textures: nothing more to draw for them.)
2. The cooked files are in `<user folder>/current/temp/art/surfacefx/marks/`. Check first: `python tools/ingest_cooked_dds.py <that folder>` (it lists any PNG with no cooked file).
3. `python tools/ingest_cooked_dds.py <that folder> --apply` copies each cooked DDS beside its PNG and removes the PNG.
4. Rerun after any change to tools/make_mark_textures.py (it rewrites the PNGs).
