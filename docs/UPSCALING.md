# DLSS / FSR as a mod: feasibility

**BeamNG 0.40 update:** 0.40 ships DLSS, FSR 3/4, XeSS and PSSR itself (`core/settings/graphic.lua`: `GraphicAntialiasType`, `GraphicUpscalingQuality` render scale 0.33-1, `GraphicUpscalingSharpness`). A mod cannot add an upscaler, but it can set these settings: Wrench Works' Mods page does ("Upscaling" group) and switches its own anti-aliasing off while a temporal upscaler is on. Frame Generation and Reflex are not in 0.40's Lua. The rest of this note is the 0.39 analysis.

What it means for Car Surface FX: the temporal upscalers reproject the picture with motion vectors, so effects drawn as post effects or flat decals can smear or ghost (drops, dirt and skid marks); the in-game check is DLSS Quality in rain against Off.

Original answer (0.39): not possible as a mod in BeamNG.drive 0.39. What a mod can do is better anti-aliasing and sharpening.

Why:
- The game has no render-scale or upscaler setting for gameplay. `core/settings/graphic.lua` only has `uiUpscaling` (the web UI) and photo-mode supersampling (`ui/photomode/capture.lua`, stills only).
- DLSS and FSR need the engine to render at a lower resolution, give the upscaler motion vectors and depth, and run it in the C++ renderer. Mods only get Lua, JBeam, materials and post-effect shaders. None of those can change the render resolution or add a native plug-in.
- A post-effect shader runs after the scene is rendered at full size, so it cannot save GPU time. It can only change how the image looks.

What we ship instead (WW `slrr/gfxMenu.lua`, the "Graphics & anti-aliasing" page in the Mods menu):
- Anti-aliasing post effects: FXAA HQ, SMAA Ultra, a temporal mode (`slrr_tsmP.hlsl`) and CAS sharpening (`slrr_casP.hlsl`). These improve the picture but cost frame time, they don't add any.
- The page shows a note when the shader files are missing.

If speed is the aim: the game's own render-quality settings and a lower resolution are the only real levers. A true upscaler would need the BeamNG developers to add it.

Not checked: whether a later game version adds an upscaler (this is for 0.39), and how the temporal mode behaves in motion in the game (offline tests only).
