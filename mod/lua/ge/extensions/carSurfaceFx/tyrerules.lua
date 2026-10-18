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
  road        = { h0 = 8.0,  margin = 0.5, k = 0.10, lo = 20,  hi = 85,  grip20 = 0.98, drop = 0.02, wearOn = 110, dry0 = 1.02, wet0 = 0.80, crr = 0.010 },
  performance = { h0 = 7.0,  margin = 0.5, k = 0.14, lo = 40,  hi = 90,  grip20 = 0.93, drop = 0.03, wearOn = 110, dry0 = 1.03, wet0 = 0.75, crr = 0.011 },
  semislick   = { h0 = 5.0,  margin = 0.4, k = 0.25, lo = 70,  hi = 104, grip20 = 0.85, drop = 0.04, wearOn = 120, dry0 = 1.04, wet0 = 0.60, crr = 0.013 },
  slick       = { h0 = 3.0,  margin = 0.3, k = 0.40, lo = 80,  hi = 105, grip20 = 0.75, drop = 0.05, wearOn = 125, dry0 = 1.00, wet0 = 0.45, crr = 0.015 },
  slicksoft   = { h0 = 3.0,  margin = 0.3, k = 0.60, lo = 85,  hi = 110, grip20 = 0.72, drop = 0.06, wearOn = 120, dry0 = 1.00, wet0 = 0.45, crr = 0.015 },
  drag        = { h0 = 3.0,  margin = 0.3, k = 0.50, lo = 60,  hi = 100, grip20 = 0.80, drop = 0.04, wearOn = 130, dry0 = 1.00, wet0 = 0.40, crr = 0.015 },
  offroad     = { h0 = 11.0, margin = 0.6, k = 0.12, lo = 0,   hi = 70,  grip20 = 1.00, drop = 0.02, wearOn = 100, dry0 = 1.00, wet0 = 0.85, crr = 0.014 },
  mud         = { h0 = 15.0, margin = 0.6, k = 0.15, lo = 0,   hi = 60,  grip20 = 1.00, drop = 0.02, wearOn = 95,  dry0 = 0.98, wet0 = 0.85, crr = 0.016 },
  winter      = { h0 = 9.0,  margin = 0.5, k = 0.12, lo = -25, hi = 15,  grip20 = 0.94, drop = 0.03, wearOn = 70,  dry0 = 1.00, wet0 = 0.80, crr = 0.011 },
  rally       = { h0 = 9.0,  margin = 0.5, k = 0.15, lo = 10,  hi = 80,  grip20 = 0.97, drop = 0.02, wearOn = 105, dry0 = 1.00, wet0 = 0.80, crr = 0.012 },
}

function M.defaults()
  return {
    enabled = true,
    wearRate = 1.0,                                         -- the time-scale of wear (research 1.4: real wear is invisible in play)
    surface = { asphalt = 1.0, concrete = 1.2, wet = 0.6, gravel = 0.5, dirt = 0.5, rock = 1.5, snow = 0.2, ice = 0.2 },
    deadZone = 0.3,                                         -- m/s of slip below which nothing is worn (rolling micro-slip)
    heatWearScale = 60, heatWearMax = 4,                    -- C over wearOn that doubles the wear, and the cap of the multiplier
    cordLimit = 1.0,                                        -- mm below zero (cord) before the tyre goes
    heatRate = 1.0, coolRate = 1.0, rainCool = 4, sunRoad = 8,
    coldGrip = 1.0, hotGrip = 1.0, pressureEffect = 1.0,
    beltGrip = 0.55, beltSliding = 0.50,
    flat = { enabled = true, minDepth = 0.2, gripLoss = 0.03 },
  }
end

-- ---- the tyre ring
function M.sectorOf(j) return math.ceil(j / 2) end
function M.laneOf(j) return j % 2 == 1 and 1 or 2 end                  -- 1 outer, 2 inner

-- a new tyre: n = numRays (16 or 20), r = radius m, w = tread width m, ambient C. Starts at the ambient temperature, optionally warm (frac of the window).
function M.new(compoundName, n, r, w, ambient, warm)
  local c = M.COMPOUNDS[compoundName] or M.COMPOUNDS.road
  local t = { compound = compoundName, c = c, n = n, r = r or 0.305, w = w or 0.175, h = {}, E = {}, flash = {}, cord = 0, blown = false }
  for j = 1, 2 * n do t.h[j] = c.h0 t.E[j] = 0 end
  for i = 1, n do t.flash[i] = 0 end
  local T0 = (ambient or 20) + (warm or 0) * (c.lo + 0.5 * (c.hi - c.lo) - (ambient or 20))
  t.Ts, t.Tc = T0, T0
  t.slotArea = 2 * math.pi * (t.r * 1000) * (t.w * 1000) / (2 * n)     -- mm2 of tread one node slot stands for
  return t
end

function M.addEnergy(t, j, joules) if t.E[j] then t.E[j] = t.E[j] + joules end end

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

-- one wear tick: the energy gathered since the last tick wears the slots (and heats their sector's flash temperature); ctx = { surface = 'asphalt'.., wet = bool, pressure, pNom }
-- Returns the deepest wear of any slot this tick (mm).
function M.wearStep(t, ctx, cfg)
  if t.blown then return 0 end
  local c, worst = t.c, 0
  local ms = cfg.surface[ctx.wet and 'wet' or (ctx.surface or 'asphalt')] or 1
  if ctx.surface == 'rock' and (t.compound == 'mud' or t.compound == 'offroad') then ms = ms * 2 end
  local mp = M.pressureWear(ctx.pressure, ctx.pNom, cfg)
  for j = 1, 2 * t.n do
    local e = t.E[j]
    if e > 0 then
      local i = M.sectorOf(j)
      local g = M.heatWear(c, t.Ts + (t.flash[i] or 0), cfg)
      local dh = c.k * (e / t.slotArea) * g * ms * mp * cfg.wearRate
      t.h[j] = math.max(-c.margin - cfg.cordLimit, t.h[j] - dh)
      if dh > worst then worst = dh end
      if t.h[j] <= -cfg.cordLimit then t.blown = true end
    end
  end
  return worst
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
  -- the flash temperature of each sector: its share of the slip power in, fast decay out
  local csec = P.Cs / t.n
  local share = (ctx.power or 0) > 0 and 1 or 0
  for i = 1, t.n do
    local e = t.E[2 * i - 1] + t.E[2 * i]
    local ps = (dt > 0 and e / dt or 0) * share
    t.flash[i] = clamp((t.flash[i] or 0) + dt * (P.as * ps * (cfg.heatRate or 1) / csec) - (t.flash[i] or 0) * dt / P.tauFlash, 0, 400)
  end
end

-- clear the accumulators after the steps of a tick have used them
function M.clearEnergy(t) for j = 1, 2 * t.n do t.E[j] = 0 end end
function M.totalEnergy(t) local s = 0 for j = 1, 2 * t.n do s = s + t.E[j] end return s end

-- ---- grip (research 8.5): multipliers on the stock node friction
function M.tempGrip(c, T, cfg)
  local cold = cfg and cfg.coldGrip or 1
  local hot = cfg and cfg.hotGrip or 1
  if T < c.lo then return 1 - (1 - c.grip20) * clamp((c.lo - T) / math.max(1, c.lo - 20), 0, 1.5) * cold end
  if T > c.hi then return math.max(0.6, 1 - c.drop * (T - c.hi) / 10 * hot) end
  return 1
end
function M.wearGrip(c, h, wet)
  local at0 = wet and c.wet0 or c.dry0
  return at0 + (1 - at0) * clamp(h / c.h0, 0, 1)
end
-- the multipliers (static, sliding) for the node slot j, to be applied to its stock coefficients; wet = the contact is wet
function M.nodeGrip(t, j, wet, cfg)
  local c = t.c
  local fT = M.tempGrip(c, t.Ts + (t.flash[M.sectorOf(j)] or 0) * 0.5, cfg)
  if t.h[j] <= 0 then return cfg.beltGrip * fT, cfg.beltSliding * fT end
  local fw = M.wearGrip(c, t.h[j], wet)
  local ff = 1
  if cfg.flat.enabled then
    local d = M.flatDepth(t, M.sectorOf(j))
    if d > cfg.flat.minDepth then ff = 1 - cfg.flat.gripLoss * clamp(d, 0, 1) end
  end
  return fT * fw * ff, fT * fw * ff
end

-- ---- looks (research 8.7): 0 new .. 4 bald, 5 belts; the stage of the worst slot, by its fraction of the tread left
M.STAGE_FROM = { 0.9, 0.7, 0.5, 0.3 }                  -- the fraction of tread left below which stages 1..4 start
function M.stage(t, cfg)
  local minH = math.huge
  for j = 1, 2 * t.n do if t.h[j] < minH then minH = t.h[j] end end
  if minH <= 0 then return 5 end
  local f, s = minH / t.c.h0, 0
  for i, lim in ipairs(M.STAGE_FROM) do if f < lim then s = i end end
  if minH <= (cfg and cfg.baldBelow or 0.5) then s = 4 end
  return s
end

-- ---- the flat-spot shake (research 2.3, 8.6): the rate (Hz) once per revolution, and the radial force it pulls on the tyre
function M.shakeHz(wheelSpeed, radius) return math.abs(wheelSpeed or 0) / (2 * math.pi * (radius or 0.31)) end
function M.shakeForce(depthMm, kRad) return (kRad or 250) * (depthMm or 0) end         -- N, 250 N/mm

return M
