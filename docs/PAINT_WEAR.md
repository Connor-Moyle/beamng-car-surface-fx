# Worn paint

`carSurfaceFx.setPaintWear(vehId, { fade = 0..1, grime = 0..1, scuffs = 0..1, rust = 0..1 })` puts a steady wear layer on a car's paint canvas. Another mod (Part Wear) calls it from one paint-condition value. All zeros (or nil) take the layer away. It does nothing unless **Worn paint (test)** is on in the Mods menu (Dirt page), and it is **not tested in game yet**.

- **fade**: big pale patches over the body (the paint loses its colour). Reads on light and mid paint; on dark paint it is a faint haze at best, because the base canvas can only darken.
- **grime**: a dark film of road dirt, low on the body and on the rear.
- **scuffs**: short scratches (the shipped scratch pictures) scattered over the body.
- **rust**: orange-brown pits (`art/surfacefx/splats/rust.png`, CC0 photographs, see TEXTURE_CREDITS.md), low on the body. Drawn on the palette layer too, so they show on dark and light paint.

The places are picked once per car from its body map (seeded by the vehicle id), and a higher value uses more of them and draws them bigger. The page draws the layer under the dirt, so washing and repair leave it alone. It is sent again to a respawned car.
