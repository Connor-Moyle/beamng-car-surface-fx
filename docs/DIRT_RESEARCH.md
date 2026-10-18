# How dirt really lands on a car

Two halves. This file covers where it lands and how it looks. The amounts (rates, caps, removal) are in `dirt-research/rules.md`, with nine suggested corrections to `rules.lua`.

The figures come from general vehicle-aerodynamics and soiling knowledge. None were measured in the game.

## Where it lands

1. **Tyre spray.** A rolling tyre throws water and mud off the tread at the speed of the car, up and back along the tangent at the contact patch's rear. Most of it is stopped by the arch and the mudflap, so the first thing to get dirty is the inside of the arch, then the sill and the lower door just ahead of the rear wheel. Lines of sprayed droplets are fanned out, so the dirt is streaks and fine speckle, thinning with distance from the wheel.
2. **Front wheels** wet the sills and the doors behind them. **Rear wheels** wet the rear bumper, the rear quarter and, behind the car, the air itself.
3. **Rear wake.** A bluff rear (hatch, SUV, van) sits in a low-pressure wake. Fine spray and road film are drawn into it and settle on the rear face, the tailgate glass and the bumper. The surface is evenly filmed, thickest at the bottom, fading up to about the roofline, and thinner on a sloping fastback. Dirt roads make this the worst-hit panel.
4. **Height gradient.** Everything above about 0.8 m is mostly dust and rain streaks. Below it is splash and film. The lowest 0.3 m, the sills and the lower bumper, carries the heaviest, coarsest dirt: cakes of mud, not film.
5. **Bonnet and windscreen.** Bugs and dust at the front edge. Spray reaches the windscreen from vehicles ahead, not from your own tyres.
6. **Underside** is always dirty. It matters only when it is seen (jumps, lifted cars).

## How it looks

| Layer | Look |
|---|---|
| Road film | Even grey-brown haze, lower body and rear. Soft edge, no particles. |
| Splash | Speckle: small dots of many sizes, denser near the wheel, in fan-shaped streaks. |
| Cakes | Thick clods in the arch lips, on the sills and at the bumper lower edge. Darker, rough edges, with dried cracked centres. |
| Streaks | Runs where rain or washed water has carried dirt downward. Vertical on panels. |
| Dried dust | Pale, matt, fades with height. Mud that dries goes lighter and cracks. |

## Against the current model

`bodymap.lua` already has the right bones: mud on the lower body, sills, the panel behind each wheel, the underside and spray traced from the tyres; grime on the lower band and rear faces fading upward; rubber at the arches. The gaps:

- The rear-face grime (`RULES.grime`, height fall-off) is the wake, but it is the same for every car shape. A fastback should get a thinner film than a hatch.
- Mud has no cakes. It is splats only. Dirt roads should build thick clods at sills, arch lips and the rear bumper (the `PLACE.mud` size is now 35 mm splats).
- No downward streaks after rain. Washed areas just fade.
- Front-wheel spray should favour the sill and door behind each front wheel. The traced spray does this, but the build is 64x64 over the paint UV, so thin sills lose detail.

## Plan

1. connor-19 makes layered textures: film, speckle, cakes, streaks.
2. connor-0f's rule corrections (see `dirt-research/rules.md`) go in as a separate change.
3. Mock-ups on the covet first, then the build.
