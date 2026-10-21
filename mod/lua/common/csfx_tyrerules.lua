-- Car Surface FX: the rules of tyre wear, temperature and flat spots (research: docs/TYRE_WEAR_RESEARCH.md in the control repo, sections 4 and 8). Pure: no game calls, so the
-- vehicle side and the game side can both load it, and tests/tyrerules_test.lua runs it outside the game. Every constant is a starting value to be tuned in the game.
--
-- A tyre is a ring of N sectors x 2 lanes (outer/inner shoulder). Node slot j (1..2N) is the tread node treadNodes[j]: odd = outer lane, even = inner lane, sector = ceil(j/2)
-- (the order of a pressureWheel's tread nodes). Energy goes in per slot (J), wear and temperature are stepped at a low rate, grip comes out per slot.
local M = {}

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
M.clamp = clamp

-- ---- compounds (research section 4). h0 tread mm, margin = how far below zero the belts/cord go before the blow-out, k mm3/J, lo/hi the grip window (C), grip20 the grip at 20 C,
-- drop the grip lost per 10 C over hi, wearOn the temperature wear starts to climb, dry0/wet0 the grip at 0 mm, crr rolling resistance
M.COMPOUNDS = {
  road        = { base = 1.0, h0 = 8.0,  margin = 0.5, k = 0.025, lo = 20,  hi = 85,  grip20 = 0.98, drop = 0.02, wearOn = 110, dry0 = 1.02, wet0 = 0.80, crr = 0.010, wetF = 1.0, aqua = 22, loose = 0.9, snow = 0.7 },
  performance = { base = 1.05, h0 = 7.0,  margin = 0.5, k = 0.035, lo = 40,  hi = 90,  grip20 = 0.93, drop = 0.03, wearOn = 110, dry0 = 1.03, wet0 = 0.75, crr = 0.011, wetF = 0.95, aqua = 20, loose = 0.85, snow = 0.65 },
  semislick   = { base = 1.12, h0 = 5.0,  margin = 0.4, k = 0.0625, lo = 70,  hi = 104, grip20 = 0.85, drop = 0.04, wearOn = 120, dry0 = 1.04, wet0 = 0.60, crr = 0.013, wetF = 0.75, aqua = 16, loose = 0.8, snow = 0.6 },
  slick       = { base = 1.2, h0 = 3.0,  margin = 0.3, k = 0.1, lo = 80,  hi = 105, grip20 = 0.75, drop = 0.05, wearOn = 125, dry0 = 1.00, wet0 = 0.45, crr = 0.015, wetF = 0.55, aqua = 12, loose = 0.7, snow = 0.5 },
  slicksoft   = { base = 1.25, h0 = 3.0,  margin = 0.3, k = 0.15, lo = 85,  hi = 110, grip20 = 0.72, drop = 0.06, wearOn = 120, dry0 = 1.00, wet0 = 0.45, crr = 0.015, wetF = 0.55, aqua = 12, loose = 0.7, snow = 0.5 },
  drag        = { base = 1.15, h0 = 3.0,  margin = 0.3, k = 0.125, lo = 60,  hi = 100, grip20 = 0.80, drop = 0.04, wearOn = 130, dry0 = 1.00, wet0 = 0.40, crr = 0.015, wetF = 0.5, aqua = 11, loose = 0.65, snow = 0.45 },
  offroad     = { base = 0.9, h0 = 11.0, margin = 0.6, k = 0.03, lo = 0,   hi = 70,  grip20 = 1.00, drop = 0.02, wearOn = 100, dry0 = 1.00, wet0 = 0.85, crr = 0.014, wetF = 1.0, aqua = 22, loose = 1.15, snow = 0.9 },
  mud         = { base = 0.85, h0 = 15.0, margin = 0.6, k = 0.0375, lo = 0,   hi = 60,  grip20 = 1.00, drop = 0.02, wearOn = 95,  dry0 = 0.98, wet0 = 0.85, crr = 0.016, wetF = 1.0, aqua = 22, loose = 1.25, snow = 0.95 },
  winter      = { base = 0.92, h0 = 9.0,  margin = 0.5, k = 0.03, lo = -25, hi = 15,  grip20 = 0.94, drop = 0.03, wearOn = 70,  dry0 = 1.00, wet0 = 0.80, crr = 0.011, wetF = 1.02, aqua = 22, loose = 1.0, snow = 1.3 },
  intermediate = { base = 0.95, h0 = 7.5, margin = 0.5, k = 0.05, lo = 25, hi = 70, grip20 = 0.90, drop = 0.04, wearOn = 85, dry0 = 0.95, dryF = 0.96, wet0 = 0.85, crr = 0.012, wetF = 1.20, aqua = 28, loose = 0.8, snow = 0.7 },
  fullwet      = { base = 0.9, h0 = 9.0, margin = 0.5, k = 0.075, lo = 15, hi = 55, grip20 = 0.92, drop = 0.06, wearOn = 70, dry0 = 0.85, dryF = 0.90, wet0 = 0.90, crr = 0.013, wetF = 1.30, aqua = 33, loose = 0.8, snow = 0.8 },
  rally       = { base = 0.97, h0 = 9.0,  margin = 0.5, k = 0.0375, lo = 10,  hi = 80,  grip20 = 0.97, drop = 0.02, wearOn = 105, dry0 = 1.00, wet0 = 0.80, crr = 0.012, wetF = 1.0, aqua = 22, loose = 1.1, snow = 0.85 },
}

function M.defaults()
  return {
    enabled = false,
    wearEnabled = true, tempGripEnabled = true, wetGripEnabled = true,       -- the parts of the simulation, each its own switch: tread wear, temperature changing grip, rain changing grip
    wearRate = 1.0,                                         -- the time-scale of wear (research 1.4: real wear is invisible in play)
    surface = { asphalt = 1.0, concrete = 1.2, wet = 0.6, gravel = 0.5, dirt = 0.5, rock = 1.5, snow = 0.2, ice = 0.2 },
    spinWear = 4,                                           -- wheelspin and cornering slip wear this many times faster than a locked wheel's sliding (a burnout reaches the belts in about 2 minutes)
    deadZone = 0.3,                                         -- m/s of slip below which nothing is worn (rolling micro-slip)
    heatWearScale = 60, heatWearMax = 3,                    -- C over wearOn that doubles the wear, and the cap of the multiplier
    cordLimit = 1.0,                                        -- mm below zero (cord) before the tyre goes
    rainAquaplane = false,                                    -- Mods settings: "Aquaplaning in heavy rain"; a thin film of water (depth up to 0.2) on the road above wetness 0.8
    rollWear = 0.2,                                          -- Mods settings: "Wear while driving"; mm of tread per 1000 km rolled on a road tyre (0.2 = 40,000 km for 8 mm)
    heatRate = 0.7, coolRate = 1.0, rainCool = 4, sunRoad = 8,
    coldGrip = 1.0, hotGrip = 1.0, pressureEffect = 1.0,
    beltGrip = 0.55, beltSliding = 0.50,
    flat = { enabled = true, minDepth = 0.2, gripLoss = 0.03 },
    -- smoke from smokeOn (full at smokeFull); fire after the surface holds igniteT for igniteHold s; a burning tyre pops after popAfter s; debris is rubber worn off (density g/mm3)
    smokeEnabled = true, sparksEnabled = true,        -- Mods settings: "Tyre smoke", "Sparks from belt-worn tyres"
    smokeOn = 90, smokeFull = 180, igniteT = 420, igniteHold = 4, burnT = 550, popAfter = 12, douse = 0.6,
    blowout = { enabled = false, strength = 1.0 },   -- Mods: "Blowouts damage nearby panels" + strength (the game side draws the panel marks; no force is applied to the car)
    look = { enabled = true, wornBelow = 0.5 },      -- the worn tyre look: on or off, and the fraction of tread left below which a tyre looks worn (the belts show at no tread)
    fires = true, fireSpread = false, spreadAfter = 4,        -- Mods settings: "Tyre fires", "Fires can spread to the car"; the car's nearest flammable node is lit after spreadAfter s of tyre fire
    debris = { enabled = true, density = 0.0011, minFrac = 0.3, maxFrac = 0.8, hotFrom = 120, hotTo = 220, pileTau = 15, pileIgniteT = 350, pileMinG = 20, pileBurnS = 12 },
    -- rubber marbles left on the road by a long burnout (Connor): the patches are kept by the game side, off by default; gripLoss is the grip lost at 100 g (twice that at 200 g and more); burn lets a hot patch burn for debris.pileBurnS; a patch hotter than glowT glows (look only); shredG is the tread a blowing tyre throws at once
    marbles = { enabled = false, gripLoss = 0.10, burn = false, lifeS = 900, maxPatches = 24, maxG = 400, mergeR = 1.5, minG = 2, burnLoss = 0.7, glowT = 200, shredG = 120 },
  }
end

-- ---- fitting a compound on a car whose stock tyre is another class: grip is relative to the stock jbeam friction, so a swap multiplies by base(new) / base(stock class)
-- (base = dry grip against a road tyre = 1). A slick on a road jbeam gains 20%, a road tyre on a slick jbeam loses 17%.
function M.swapRatio(stock, new)
  local a, b = M.COMPOUNDS[stock or 'road'], M.COMPOUNDS[new or stock or 'road']
  return (a and b) and b.base / a.base or 1
end
-- save and load of a tyre's state (JSON-safe: numbers rounded to 0.01 mm). Flat spots follow from the depths, so only the depths are kept.
function M.snapshot(t)
  local h = {}
  for j = 1, 2 * t.n do h[j] = math.floor(t.h[j] * 100 + 0.5) / 100 end
  return { compound = t.compound, n = t.n, h = h, cord = t.cord, blown = t.blown or false }
end
function M.restore(t, blob)
  if type(blob) ~= 'table' or blob.n ~= t.n or type(blob.h) ~= 'table' then return false end
  local lo = -t.c.margin - 3                                               -- (the deepest wearStep goes: margin + the largest cordLimit)
  for j = 1, 2 * t.n do local x = blob.h[j] if type(x) == 'number' and x == x then t.h[j] = clamp(x, lo, t.c.h0) end end       -- a saved NaN or out-of-range depth must not reach the grip
  t.cord, t.blown = tonumber(blob.cord) or 0, blob.blown and true or false
  return true
end

-- ---- the tyre ring
function M.sectorOf(j) return math.ceil(j / 2) end
function M.laneOf(j) return j % 2 == 1 and 1 or 2 end                  -- 1 outer, 2 inner

-- a new tyre: n = numRays (16 or 20), r = radius m, w = tread width m, ambient C. Starts at the ambient temperature, optionally warm (frac of the window).
function M.new(compoundName, n, r, w, ambient, warm)
  local c = M.COMPOUNDS[compoundName] or M.COMPOUNDS.road
  local t = { compound = compoundName, c = c, n = n, r = r or 0.305, w = w or 0.175, h = {}, E = {}, EL = {}, flash = {}, cord = 0, blown = false }
  for j = 1, 2 * n do t.h[j] = c.h0 t.E[j] = 0 t.EL[j] = 0 end
  for i = 1, n do t.flash[i] = 0 end
  local T0 = (ambient or 20) + (warm or 0) * (c.lo + 0.5 * (c.hi - c.lo) - (ambient or 20))
  t.Ts, t.Tc = T0, T0
  t.slotArea = 2 * math.pi * (t.r * 1000) * (t.w * 1000) / (2 * n)     -- mm2 of tread one node slot stands for
  return t
end

-- lock = the wheel is sliding locked (its slip energy wears at the low flat-spot rate); anything else (wheelspin, cornering) wears spinWear times faster
function M.addEnergy(t, j, joules, lock)
  if t.E[j] then t.E[j] = t.E[j] + joules if lock then t.EL[j] = t.EL[j] + joules end end
end

-- energy P*dt of a rolling or sliding wheel at the contact node j (research 8.2 B): the whole ring is fed round when it rolls, one slot when it is locked
function M.slipPower(slipVel, normalForce, mu, deadZone)
  local v = math.max(0, (slipVel or 0) - (deadZone or 0.3))
  return v * (normalForce or 0) * (mu or 1)
end

-- ---- wear (research 8.3)
function M.pressureWear(p, pNom, cfg)
  if not (p and pNom and pNom > 0) then return 1 end
  local e = cfg and cfg.pressureEffect or 1
  return 1 + e * (1.5 * math.max(0, (pNom - p) / pNom) + 0.8 * math.max(0, (p - pNom) / pNom))
end
function M.heatWear(c, Teff, cfg)
  return clamp(1 + math.max(0, Teff - c.wearOn) / cfg.heatWearScale, 1, cfg.heatWearMax)
end

local WEAR_ALIAS = { mud = 'dirt', sand = 'dirt', grass = 'dirt' }       -- surfaces the wear table has no key for
-- one wear tick: the energy gathered since the last tick wears the slots (and heats their sector's flash temperature); ctx = { surface = 'asphalt'.., wet = bool, pressure, pNom }
-- Returns the deepest wear of any slot this tick (mm).
function M.wearStep(t, ctx, cfg)
  if t.blown or cfg.wearEnabled == false then return 0 end
  local c, worst = t.c, 0
  local sk = ctx.wet and 'wet' or (ctx.surface or 'asphalt')
  local ms = cfg.surface[sk] or cfg.surface[WEAR_ALIAS[sk] or ''] or 1
  if ctx.surface == 'rock' and (t.compound == 'mud' or t.compound == 'offroad') then ms = ms * 2 end
  local mp = M.pressureWear(ctx.pressure, ctx.pNom, cfg)
  local roll = (ctx.dist or 0) > 0 and (cfg.rollWear or 0) * 1e-6 * ctx.dist * (c.k / M.COMPOUNDS.road.k) * ms * mp * cfg.wearRate * (cfg.wearScale or 1) or 0     -- plain rolling: the whole ring, whatever the slip
  for j = 1, 2 * t.n do
    local e = t.E[j]
    if roll > 0 and t.h[j] > -c.margin - cfg.cordLimit then
      t.h[j] = t.h[j] - roll * M.heatWear(c, t.Ts, cfg)
      if t.h[j] <= -cfg.cordLimit then t.blown = true end
    end
    if e > 0 then
      e = t.EL[j] + (e - t.EL[j]) * (cfg.spinWear or 1)
      local i = M.sectorOf(j)
      local g = M.heatWear(c, t.Ts + (t.flash[i] or 0), cfg)
      local dh = c.k * (e / t.slotArea) * g * ms * mp * cfg.wearRate * (cfg.wearScale or 1)       -- (wearScale: the career's wear rate, set by Street Legal for the session, not a setting of this page)
      t.h[j] = math.max(-c.margin - cfg.cordLimit, t.h[j] - dh)
      t.shed = (t.shed or 0) + dh * t.slotArea
      if dh > worst then worst = dh end
      if t.h[j] <= -cfg.cordLimit then t.blown = true end
    end
  end
  return worst
end

-- ---- debris, smoke and fire (Connor, 2026-10-19). Rubber worn off is thrown as chunks, more of it and more loose the hotter the surface (a burnout throws marbles, a cool wear is dust).
-- takeDebris returns the grams to drop since the last call and the surface temperature it leaves at (the temperature the pile starts at).
function M.takeDebris(t, cfg)
  local d = cfg.debris
  if d.enabled == false then t.shed = 0 return 0, t.Ts end
  local frac = d.minFrac + (d.maxFrac - d.minFrac) * clamp((t.Ts - d.hotFrom) / (d.hotTo - d.hotFrom), 0, 1)
  local g = (t.shed or 0) * d.density * frac
  t.shed = 0
  return g, t.Ts
end
-- a pile of hot debris on the road: { g, T, burn }. Cools to the ambient; a big enough pile still above pileIgniteT burns for pileBurnS s (burn counts down).
function M.pileStep(p, dt, ambient, wet, cfg)
  local d = cfg.debris
  p.T = ambient + (p.T - ambient) * math.exp(-dt / (d.pileTau / (1 + 2 * clamp(wet or 0, 0, 1))))
  if (p.burn or 0) > 0 then p.burn = p.burn - dt
  elseif p.g >= d.pileMinG and p.T >= d.pileIgniteT then p.burn = d.pileBurnS end
  return (p.burn or 0) > 0
end
-- smoke 0..1 from the surface temperature
function M.smoke(Ts, cfg) if cfg.smokeEnabled == false then return 0 end return clamp((Ts - cfg.smokeOn) / (cfg.smokeFull - cfg.smokeOn), 0, 1) end
-- one fire tick. Ignites after the hottest surface (Ts + a quarter of the worst flash) holds igniteT for igniteHold s; while burning the surface sits at burnT, water/rain (wet) douses it
-- (douse per s at wet 1) and it pops (blown) after popAfter s of fire. Returns 'ignite' / 'pop' / 'out' the tick it happens, else nil.
local FLASH_FIRE = 0.25      -- a locked slide heats one spot to the flash cap in seconds; only a quarter of that counts toward a fire (a skid smokes and flats, a long burnout burns)
function M.fireStep(t, dt, wet, cfg)
  if t.blown then t.fire, t.hold = nil, 0 return end
  local hot = t.Ts
  for i = 1, t.n do if (t.flash[i] or 0) * FLASH_FIRE + t.Ts > hot then hot = t.Ts + t.flash[i] * FLASH_FIRE end end
  if not t.fire then
    if cfg.fires == false then t.hold = 0 return end
    t.hold = hot >= cfg.igniteT and (t.hold or 0) + dt or 0
    if t.hold >= cfg.igniteHold then t.fire, t.hold = 0, 0 return 'ignite' end
    return
  end
  t.fire = t.fire + dt
  t.Ts = math.max(t.Ts, cfg.burnT)
  if (wet or 0) * cfg.douse * t.fire > 1 then t.fire, t.spread = nil, nil t.Ts = t.Ts * 0.5 return 'out' end
  if cfg.fireSpread and not t.spread and t.fire >= cfg.spreadAfter then t.spread = true return 'spread' end
  if t.fire >= cfg.popAfter then t.fire, t.blown, t.spread = nil, true, nil return 'pop' end
end

-- how much shallower a sector is than its two neighbours, in mm (the flat spot), counting the shallower lane
function M.flatDepth(t, i)
  local n = t.n
  local function dep(s) s = (s - 1) % n + 1 return math.min(t.h[2 * s - 1], t.h[2 * s]) end
  return ((dep(i - 1) + dep(i + 1)) / 2) - dep(i)
end
function M.worstFlat(t)
  local w, at = 0, nil
  for i = 1, t.n do local d = M.flatDepth(t, i) if d > w then w, at = d, i end end
  return w, at
end

-- ---- temperature (research 8.4). Lumped surface + core temperature per tyre, a flash temperature per sector.
-- ctx = { dt, power (W of slip power into the tyre this tick, all slots), v (m/s), fz (N), ambient, road (C), wet (0..1), brake (C or nil), pressure, pNom }
-- Cs: the surface is a thin layer (~0.7 mm of rubber over the contact ring), so a burnout spikes it in seconds while the carcass (Cc) lags; Gsc is the slow link between them
local P = { Cs = 500, Cc = 10000, as = 0.5, bs = 0.3, h0 = 10, h1 = 5, Aout = 0.6, Groad = 30, Gsc = 30, Gin = 15, Gbrake = 5, tauFlash = 2 }
M.THERMAL = P
function M.tempStep(t, ctx, cfg)
  local dt = clamp(ctx.dt or 0.05, 0, 0.1)
  if dt <= 0 then return end
  local c, v = t.c, math.abs(ctx.v or 0)
  local amb = ctx.ambient or 20
  local road = ctx.road or amb + (cfg.sunRoad or 0)
  local pr = ctx.pressure and ctx.pNom and ctx.pressure > 0 and math.sqrt(ctx.pNom / ctx.pressure) or 1
  local Pslip = (ctx.power or 0) * (cfg.heatRate or 1)
  local Proll = c.crr * (ctx.fz or 0) * v * pr
  local rain = 1 + (cfg.rainCool - 1) * clamp(ctx.wet or 0, 0, 1)
  local cool = (cfg.coolRate or 1)
  local hconv = (P.h0 + P.h1 * v ^ 0.8) * P.Aout * rain * cool
  local inContact = (ctx.fz or 0) > 100 and 1 or 0
  local Ts, Tc = t.Ts, t.Tc
  local dTs = (P.as * Pslip + P.bs * Proll - hconv * (Ts - amb) - P.Groad * inContact * cool * (Ts - road) - P.Gsc * (Ts - Tc)) / P.Cs
  local dTc = ((1 - P.bs) * Proll + P.Gsc * (Ts - Tc) - P.Gin * cool * (Tc - amb) + (ctx.brake and P.Gbrake * (ctx.brake - Tc) or 0)) / P.Cc
  t.Ts, t.Tc = Ts + dTs * dt, Tc + dTc * dt
  if not (t.Ts > -273 and t.Ts < 3000 and t.Tc > -273 and t.Tc < 3000) then t.Ts, t.Tc = amb, amb for i = 1, t.n do t.flash[i] = 0 end end   -- NaN or runaway input (a bad wheel speed): start over at the ambient, never keep it
  -- the flash temperature of each sector: its share of the slip power in, fast decay out
  local csec = P.Cs / t.n
  local share = (ctx.power or 0) > 0 and 1 or 0
  for i = 1, t.n do
    local e = t.E[2 * i - 1] + t.E[2 * i]
    local ps = (dt > 0 and e / dt or 0) * share
    local f = clamp((t.flash[i] or 0) + dt * (P.as * ps * (cfg.heatRate or 1) / csec) - (t.flash[i] or 0) * dt / P.tauFlash, 0, 400)
    t.flash[i] = f == f and f or 0
  end
end

-- clear the accumulators after the steps of a tick have used them
function M.clearEnergy(t) for j = 1, 2 * t.n do t.E[j] = 0 t.EL[j] = 0 end end
function M.totalEnergy(t) local s = 0 for j = 1, 2 * t.n do s = s + t.E[j] end return s end

-- ---- grip (research 8.5): multipliers on the stock node friction
function M.tempGrip(c, T, cfg)
  if cfg and cfg.tempGripEnabled == false then return 1 end
  local cold = cfg and cfg.coldGrip or 1
  local hot = cfg and cfg.hotGrip or 1
  if T < c.lo then return 1 - (1 - c.grip20) * clamp((c.lo - T) / math.max(1, c.lo - 20), 0, 1.5) * cold end
  if T > c.hi then return math.max(0.6, 1 - c.drop * (T - c.hi) / 10 * hot) end
  return 1
end
-- wet = true/false or 0..1 (how wet the surface is). Dry: dry0 at 0 mm to dryF (default 1) at full tread. Wet: wet0 at 0 mm to wetF (the compound against a road tyre on the same wet road) at full tread.
function M.wearGrip(c, h, wet)
  local w = wet == true and 1 or (wet and wet ~= false and clamp(wet, 0, 1) or 0)
  local f = clamp(h / c.h0, 0, 1)
  local dry = c.dry0 + ((c.dryF or 1) - c.dry0) * f
  if w <= 0 then return dry end
  local wetG = c.wet0 + ((c.wetF or 1) - c.wet0) * f
  return dry + (wetG - dry) * w
end
-- standing water: above the compound's aquaplaning speed (lower with less tread) the grip falls away, up to 80% at depth 1
function M.aquaplane(c, h, water, v)
  if (water or 0) <= 0 then return 1 end
  local va = (c.aqua or 22) * (0.4 + 0.6 * clamp(h / c.h0, 0, 1))
  return 1 - 0.8 * clamp(water, 0, 1) * clamp((math.abs(v or 0) - va) / 8, 0, 1)
end
-- loose ground and snow suit some compounds: surface = 'dirt' | 'gravel' | 'mud' | 'sand' | 'snow' | anything else (no change)
local LOOSE = { dirt = 'loose', gravel = 'loose', mud = 'loose', sand = 'loose', grass = 'loose', snow = 'snow' }
-- the game's ground model name (e.g. 'DIRT_DUSTY', 'ASPHALT_WET') -> a surface key (mud, sand and grass wear like dirt: WEAR_ALIAS above)
local GROUND_KEYS = { 'ice', 'snow', 'mud', 'sand', 'grass', 'gravel', 'rock', 'dirt', 'concrete', 'asphalt' }      -- first match wins (a snowy road is snow)
function M.surfaceOfGround(name)
  local n = tostring(name or ''):lower()
  for _, k in ipairs(GROUND_KEYS) do if n:find(k, 1, true) then return k end end
  if n:find('tarmac', 1, true) or n:find('road', 1, true) or n:find('cobble', 1, true) or n:find('brick', 1, true) or n:find('paved', 1, true) then return 'asphalt' end
  return nil
end
function M.surfaceGrip(c, surface) local f = LOOSE[surface or ''] return f and c[f] or 1 end
-- the multipliers (static, sliding) for the node slot j, to be applied to its stock coefficients; wet = the contact is wet
function M.nodeGrip(t, j, wet, cfg, ctx)
  local c = t.c
  local fT = M.tempGrip(c, t.Ts + (t.flash[M.sectorOf(j)] or 0) * 0.5, cfg)
  local function fin(x) return x == x and x or 1 end                  -- never hand the engine a NaN friction
  if t.h[j] <= 0 then return fin(cfg.beltGrip * fT), fin(cfg.beltSliding * fT) end
  local wetOn = cfg.wetGripEnabled ~= false
  local fw = M.wearGrip(c, t.h[j], wetOn and wet)
  if ctx then fw = fw * (wetOn and M.aquaplane(c, t.h[j], ctx.water, ctx.v) or 1) * M.surfaceGrip(c, ctx.surface) end
  local ff = 1
  if cfg.flat.enabled then
    local d = M.flatDepth(t, M.sectorOf(j))
    if d > cfg.flat.minDepth then ff = 1 - cfg.flat.gripLoss * clamp(d, 0, 1) end
  end
  return fin(fT * fw * ff), fin(fT * fw * ff)
end

-- ---- looks (research 8.7): 0 new .. 4 bald, 5 belts; the stage of the worst slot, by its fraction of the tread left
M.STAGE_FROM = { 0.9, 0.7, 0.5, 0.3 }                  -- the fraction of tread left below which stages 1..4 start
function M.stage(t, cfg)
  local minH = math.huge
  for j = 1, 2 * t.n do if t.h[j] < minH then minH = t.h[j] end end
  if minH <= 0 then return 5 end
  local f, s = minH / t.c.h0, 0
  local worn = (cfg and cfg.look and cfg.look.wornBelow) or M.STAGE_FROM[3]
  for i, lim in ipairs({ M.STAGE_FROM[1], M.STAGE_FROM[2], worn, math.min(M.STAGE_FROM[4], worn) }) do if f < lim then s = i end end      -- (stage 3 is where the look turns worn: the setting)
  if minH <= 0.5 then s = math.max(s, 4) end
  return s
end

-- ---- the flat-spot shake (research 2.3, 8.6): the rate (Hz) once per revolution, and the radial force it pulls on the tyre
function M.shakeHz(wheelSpeed, radius) return math.abs(wheelSpeed or 0) / (2 * math.pi * (radius or 0.31)) end
function M.shakeForce(depthMm, kRad) return (kRad or 250) * (depthMm or 0) end         -- N, 250 N/mm

-- ---- rubber marbles on the road (Connor 2026-10-21): patches {x, y, z, g, T, born, burn} that merge, decay, cool, burn and slow a tyre rolling over them. Pure: the GE module keeps the list and draws it.
-- a patch of g grams: the radius of the patch grows from 0.5 m to mergeR with the load
function M.marbleRadius(g, cfg) local m = cfg.marbles return 0.5 + (m.mergeR - 0.5) * clamp(g / m.maxG, 0, 1) end
-- add `g` grams at (x, y, z) at temperature T: into the patch within mergeR if there is one, else a new patch (the oldest goes when there are maxPatches). Returns the patch.
function M.marbleAdd(list, x, y, z, g, T, now, cfg)
  local m = cfg.marbles
  if not (g > 0 and x == x and y == y) then return nil end                -- no grams, or a NaN position: nothing to add
  local best, bd
  for _, p in ipairs(list) do
    local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
    if d <= m.mergeR * m.mergeR and (not bd or d < bd) then best, bd = p, d end
  end
  if best then
    local tot = best.g + g
    best.T = (best.T * best.g + T * g) / math.max(tot, 1e-6)       -- the temperature of the mix
    best.x, best.y = (best.x * best.g + x * g) / math.max(tot, 1e-6), (best.y * best.g + y * g) / math.max(tot, 1e-6)   -- the centre moves to the centroid: two spinning wheels leave one heap between them
    best.g = math.min(tot, m.maxG)
    return best
  end
  if #list >= m.maxPatches then
    local oi = 1
    for i, p in ipairs(list) do if p.born < list[oi].born then oi = i end end
    table.remove(list, oi)
  end
  local p = { x = x, y = y, z = z, g = math.min(g, m.maxG), T = T, born = now, burn = 0 }
  list[#list + 1] = p
  return p
end
-- one step of every patch: it cools (pileStep), decays over lifeS (three times faster in the wet), burns when it may, and goes below minG. Returns how many patches burn now.
function M.marbleStep(list, dt, ambient, wet, cfg)
  local m, burning = cfg.marbles, 0
  for i = #list, 1, -1 do
    local p = list[i]
    local was = (p.burn or 0) > 0
    local on = M.pileStep(p, dt, ambient, wet, cfg)
    if not m.burn then p.burn, on = 0, false end
    if was and not on then p.g = p.g * (1 - m.burnLoss) end          -- the fire used the rubber up
    if on then burning = burning + 1 end
    p.g = p.g * math.exp(-dt / (m.lifeS / (1 + 2 * clamp(wet or 0, 0, 1))) * 3)
    if p.g < m.minG then table.remove(list, i) end
  end
  return burning
end
-- the share of a patch's grams a wheel scuffs away when it drives over it
function M.marbleScuff(p, frac) p.g = p.g * (1 - clamp(frac or 0, 0, 1)) end
-- the grip multiplier of a tyre on a patch of g grams (1 = none)
function M.marbleGrip(g, cfg) local m = cfg.marbles return 1 - clamp(m.gripLoss, 0, 0.3) * clamp((g or 0) / 100, 0, 2) end
-- the patch under the point (x, y): its index, or nil
function M.marbleAt(list, x, y, cfg)
  for i, p in ipairs(list) do
    local r = M.marbleRadius(p.g, cfg)
    if (p.x - x) ^ 2 + (p.y - y) ^ 2 <= r * r then return i, p end
  end
end

return M
