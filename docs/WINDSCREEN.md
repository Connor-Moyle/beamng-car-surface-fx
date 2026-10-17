# Windscreen (result, 2026-10-17)

The imgui overlay (screen-space drops, wiper sweep) was built and tried in game (commit 5f40049..fc15968, see git history): imgui is disabled in a play session
(`Engine.imgui.isEnabled()` and `ui_visibility.getImgui()` both false; forcing it on would also show every other debug window), so nothing can be drawn there. Removed.

Now: the same water beads as on the paint, on the glass materials (names containing "glass", not "dmg"/"broken"), first stage only, in place, strength by wetness
(`rules.glassFields`). The wipers (vehicle side: highest `electrics.values` key containing "wiper") put the glass back to dry while above 0.1.
Setting `windscreen.enabled` (default true). Limits: static beads, no running streaks, no per-drop wiper sweep; glass with its own detail map is left alone.
Next option if this is not enough: a CEF (UI app) layer with a canvas, which does render in play.
