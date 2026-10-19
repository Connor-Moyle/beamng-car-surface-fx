# Tyres settings: the cfg schema for the Mods "Tyres" page

Source of truth: `M.defaults()` in `mod/lua/common/csfx_tyrerules.lua`. Keys are cfg paths. `N` = normal (always shown), `A` = under Show advanced. Ranges are the slider limits. Per-compound overrides (tab Compounds) edit fields of `M.COMPOUNDS[name]`.

| Tab | Key | Default | Range | Level | Meaning |
|---|---|---|---|---|---|
| (top) | enabled | **false** (shipped off) | on/off | N | the whole tyre simulation |
| Wear | wearRate | 1.0 | 0 - 20 | N | time scale of wear (real wear is invisible in play) |
| Wear | surface.asphalt / concrete / wet / gravel / dirt / rock / snow / ice | 1 / 1.2 / 0.6 / 0.5 / 0.5 / 1.5 / 0.2 / 0.2 | 0 - 3 each | A | wear multiplier per surface |
| Wear | deadZone | 0.3 | 0 - 2 m/s | A | slip below this wears nothing |
| Wear | heatWearScale | 60 | 10 - 200 C | A | C over the compound's wearOn that doubles wear |
| Wear | heatWearMax | 4 | 1 - 10 | A | cap of the heat wear multiplier |
| Wear | cordLimit | 1.0 | 0 - 3 mm | A | how far below zero tread the tyre goes before it blows |
| Wear | flat.enabled | true | on/off | N | flat spots from locked skids |
| Wear | flat.minDepth | 0.2 | 0 - 2 mm | A | flat spot depth that starts to matter |
| Wear | flat.gripLoss | 0.03 | 0 - 0.2 | A | grip lost per mm of flat spot |
| Temperature | heatRate | 1.0 | 0.1 - 5 | N | how fast slip heats the tyre |
| Temperature | coolRate | 1.0 | 0.1 - 5 | N | how fast it cools |
| Temperature | rainCool | 4 | 1 - 10 | A | cooling factor at full wet |
| Temperature | sunRoad | 8 | 0 - 30 C | A | road warmer than the air by this much |
| Grip | coldGrip | 1.0 | 0 - 2 | N | how much a cold tyre loses |
| Grip | hotGrip | 1.0 | 0 - 2 | N | how much an overheated tyre loses |
| Grip | pressureEffect | 1.0 | 0 - 2 | A | pressure effect on grip and wear |
| Grip | beltGrip / beltSliding | 0.55 / 0.50 | 0.2 - 1 | A | grip once the tread is gone (belts) |
| Grip | baldBelow | 0.5 | 0 - 2 mm | A | tread under which it looks bald |
| Wet | rainCool | (see Temperature) | | | |
| Fire & debris | fires | true | on/off | N | "Tyre fires" |
| Fire & debris | fireSpread | **false** (unproven) | on/off | N | "Fires can spread to the car" |
| Fire & debris | spreadAfter | 4 | 1 - 20 s | A | s of tyre fire before the car's nearest flammable node is lit |
| Fire & debris | smokeOn / smokeFull | 150 / 250 | 80 - 400 C | A | smoke starts and is full |
| Fire & debris | igniteT | 350 | 200 - 600 C | A | surface temperature that ignites |
| Fire & debris | igniteHold | 2 | 0.5 - 10 s | A | seconds it must hold igniteT |
| Fire & debris | burnT | 550 | 400 - 800 C | A | temperature of a burning tyre |
| Fire & debris | popAfter | 8 | 2 - 60 s | A | burning tyre pops after this |
| Fire & debris | douse | 0.6 | 0 - 3 | A | rain/water dousing strength |
| Fire & debris | debris.density | 0.0011 | fixed | A | g per mm3 of rubber |
| Fire & debris | debris.minFrac / maxFrac | 0.3 / 0.8 | 0 - 1 | N | share of worn rubber thrown as debris (cool / hot); a single "Debris amount" slider scales both |
| Fire & debris | debris.hotFrom / hotTo | 120 / 220 | 50 - 400 C | A | temperature span for the share |
| Fire & debris | debris.pileTau | 15 | 2 - 120 s | A | cooling time of a pile |
| Fire & debris | debris.pileIgniteT | 350 | 150 - 600 C | A | hot pile catches above this |
| Fire & debris | debris.pileMinG | 20 | 1 - 200 g | A | smallest pile that can catch |
| Fire & debris | debris.pileBurnS | 12 | 2 - 120 s | A | pile burn time |
| Fire & debris | blowout.enabled | **false** | on/off | N | "Blowouts damage nearby panels" (off until shown in game) |
| Fire & debris | blowout.strength | 1.0 | 0 - 3 | N | force scale (still capped) |
| Fire & debris | blowout.radius | 0.5 | 0.2 - 0.8 m | A | search radius around the wheel |
| Fire & debris | blowout.maxNodes | 4 | 1 - 8 | A | nodes pushed |
| Fire & debris | blowout.steps | 3 | 1 - 5 | A | physics steps of the push |
| Fire & debris | blowout.maxForce | 3000 | 500 - 3000 N | A | hard cap per node (never raise the max above 3000) |
| Fire & debris | blowout.chance0 / chance100 | 0.15 / 0.9 | 0 - 1 | A | chance at standstill / at 100 km/h |
| Visuals | (stage thresholds `M.STAGE_FROM` {0.9,0.7,0.5,0.3}, tread fade) | | | A | not in cfg yet; will be added with the visual build |
| Compounds | per compound: h0, k, lo, hi, grip20, drop, wearOn, dry0, dryF, wet0, wetF, aqua, loose, snow, base, crr | see COMPOUNDS | | A | overrides of the table for road, performance, semislick, slick, slicksoft, drag, offroad, mud, winter, rally, intermediate, fullwet |

## Presets (one table of cfg overrides each)
- **Realistic** (default): the defaults above, `blowout.enabled` false until proven.
- **Arcade**: wearRate 0.3, heatRate 0.6, coldGrip 0.3, hotGrip 0.3, flat.enabled false, fires false, blowout.enabled false.
- **Off**: enabled false (stock tyres, nothing else runs).
