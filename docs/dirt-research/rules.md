# Dirt rules: what `rules.lua` does today, against how it works in reality

Scope: the amount rules only (how fast each kind builds up, what removes it). Where dirt lands on the car is the placement section (ba); how it looks is connor-19's.
Source: `mod/lua/ge/extensions/carSurfaceFx/rules.lua` on `bodywear-rewrite` (dirtBuild, dirtWash, dirtClean, the bug/dust helpers). Every amount is 0..1 per kind and capped at `CAP`. The build-up setting `settings.mud.rate` multiplies `dt`, so every "seconds" figure below is at rate 1.

Shared factors in `dirtBuild`: `sf = 0.4 + 0.6 * clamp(v/20, 0, 1)` (a car at rest still collects 40%, saturates at 20 m/s = 72 km/h); `wetK = clamp(wet*1.5, 0, 1)`; `wet` is the road/rain wetness 0..1. Ground class comes from the ground-model name (`groundClass`): mud 1, clay 0.7, dirt 0.6, sand 0.5, gravel 0.5, grass 0.25, snow 0.15, rock 0.15 (loose); asphalt, concrete, tarmac, road, cobble, paved, brick (road).

## Rule table (rates at sf = 1, i.e. 20 m/s or more)

| Kind | Builds when | Rate | Cap | Removed by |
|---|---|---|---|---|
| dust | loose ground, dry (`loose * (1-wetK)`) | 1/60 per s x weight: full in 86 s on clay, 100 s on dirt, 120 s on gravel/sand, 240 s on grass | 1 | rain: 60 s of full rain; water: 3 s; wash |
| dust | dry road (`road * (1-wetK)`) | 1/400 per s (6.7 min) | 1 | same |
| mud | mud ground, or loose ground in the wet (`mud + loose*wetK`) | 1/90 per s, times (1 + 0.5 wet): 60-90 s | 1 | rain: 420 s; water: 12 s; wash |
| grime | road | 1/1200 per s, times (1 + wet): 20 min dry, 10 min wet | 0.6 | rain: 900 s; water: 40 s; wash |
| rubber | wheel slip (`slip` share) | 1/25 per s of skidding | 1 | rain: 6000 s; water: 200 s; wash |
| snow | snowing, air below 1.5 C | 1/90 per s standing (x0.15 moving) | 1 | blown off above 8 m/s at (v-8)/40 per s; melts above 1.5 C at 1/900 per s; rain 400 s; water 15 s |
| bugs | speed above 18 m/s, air 8..18 C ramps in, none at rain 0.3+ | (v-18)/20/300 per s x activity: 1/300 at 38 m/s (nose full-cap 0.5 in 150 s); 1/857 at 25 m/s | 0.5 | rain: 500 s scaled by soak (x0.25 at once, x1 after 90 s of rain); water 30 s; wash |

Rain wash is `wet*dt/RAIN[k]`, water wash is `waterShare*dt/WATER[k]`. A car wash takes `amount` off every kind. Dust also has a presentation rule: the film climbs with `dustHeight = amount^0.7` and rain clears it from the top down over 60 s (`dustWashHeight`).

## Where it differs from reality, with suggested numbers

1. **A standing car collects dirt.** `sf` has a 0.4 floor, so a parked car on a wet dirt road still gains mud. Real mud is flung by wheel rotation and spray scales with speed (roughly v^2). Fix: `sf = 0.1 + 0.9 * clamp((v/30)^1.5, 0, 1)` and only the `slip`/wheel-spin share keeps a floor of 0.3 at v < 3. Standing in the rain should add no mud; it still adds snow by `snowing`.

2. **Saturation at 20 m/s is too early.** Fast roads (30-40 m/s) throw far more spray than 20 m/s. The `(v/30)^1.5` form gives 0.54 at 20 m/s, 1.0 at 30 and 1.5 at 40 (before the clamp, which should go: cap it at 1.5). Multiply the rate constants by 1.85 to keep today's numbers at 20 m/s.

3. **Wet tarmac makes no mud, only 2x grime.** Real wet roads throw a dirty road-film spray that is mostly the dirtiest thing a car meets on a drive in the rain. Fix: on road, add `road * wetK * sf * dt / 400` to grime (instead of the current `(1+wet)` factor, 3x faster at full wet) and let it reach the cap 0.6 in about 7 min. Dry road dust stays 1/400.

4. **Rain washes mud and grime away too well, dust too completely.** Real rain does not clean a car: it streaks dust, softens mud (re-wets, then it runs), and leaves a road film in place (it adds to it). Suggestions: grime `RAIN` 900 -> 3600 (rain barely moves it); mud 420 -> 1200 (only an hour-scale shower clears it); dust stays fast at 60 s but converts to grime: of every dust unit rain removes, add 0.3 to grime (cap 0.6) so a dusty car after a shower is streaky, not clean. Rubber is right (practically permanent).

5. **Dry dust and mud never leave on their own.** Highway wind removes loose dust from horizontal panels, and dried mud flakes off with vibration. Add: dust decay `max(0, v-25) * dt / 1500` (gone in a few minutes at 40 m/s), dry mud decay `(v > 12 and wet < 0.1) and dt / 1800 or 0` (30 min), nothing for grime and rubber.

6. **Water wash ignores the water level.** `water` is the share of time a wheel was in water, so it cleans the whole car equally, though a deep ford wets only the lower body and splashes the rest with muddy water. Fix: scale water wash by depth (wheel in 0.2 m: only the lowest 20% of the height, which pairs with the height model), and add a mud gain of `0.2 * water` when the water is muddy (ground class is mud/clay under the water).

7. **Bugs: temperature ramp too cold.** Insects fly above about 10-13 C and peak at 20-28 C. Today the ramp is 8 -> 18 C. Fix: `BUG_COLD = 12`, `BUG_WARM = 22`, and the "too hot" cut at 38 C stays. Dusk gain 1.4 is right (insects are densest at dusk and dawn). The speed threshold of 18 m/s is fine for hitting the nose; add `bugRate` x1.5 for tall flat noses (vans) only if the bodymap gives a nose area.

8. **Snow melt only above 1.5 C and a snowing car at rest takes all.** Fine for a game. One fix: snow that lands on a warm engine bay area melts first, but that is a placement matter (ba).

9. **Time scale.** All rates compress days into minutes; that is intended (a dirty car after one drive session). The grime cap of 0.6 and the bug cap of 0.5 make a car that is never washed look dirty, not ruined; keep them. If the level of dirt after one hour of mixed driving feels low to a player, raise `settings.mud.rate`; do not change the per-kind constants.

## Test data to keep
The rules have luatest cases in `tests/`. Any change above that alters a rate should add a number to the same test (for example "mud on dirt at 20 m/s for 100 s is at least 0.9").

## Not checked
Rates were read from the code, not measured in the game. The real-world figures here are from general knowledge of how cars get dirty (spray, road film, insects); none is from a measured source, so treat the suggested constants as starting points for a tuning pass.
