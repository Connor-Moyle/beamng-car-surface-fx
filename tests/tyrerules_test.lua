-- Tyre rules (tyrerules.lua): sectors, Archard wear, flat spot from a locked skid, temperature heat and cool, the grip curve and the looks. No game calls.
local R = require('carSurfaceFx/tyrerules')
local cfg = R.defaults()
local function near(a, b, tol, msg) assert(math.abs(a - b) <= tol, (msg or 'near') .. ': ' .. tostring(a) .. ' vs ' .. tostring(b)) end

-- ---- sectors: slot j (1..2N) is a tread node, odd = outer lane, even = inner, two slots to a sector
assert(R.sectorOf(1) == 1 and R.sectorOf(2) == 1 and R.sectorOf(3) == 2 and R.sectorOf(32) == 16 and R.sectorOf(40) == 20, 'two slots to a sector')
assert(R.laneOf(1) == 1 and R.laneOf(2) == 2 and R.laneOf(31) == 1, 'outer is odd, inner is even')
local t = R.new('road', 16, 0.305, 0.175, 20)
assert(#t.h == 32 and t.h[1] == 8.0 and t.Ts == 20 and not t.blown, 'a new tyre: 8 mm everywhere, at the ambient temperature')
near(t.slotArea, 2 * math.pi * 305 * 175 / 32, 0.01, 'one slot stands for a 32nd of the tread')
assert(R.new('road', 20).slotArea < t.slotArea, 'twenty rays: smaller slots')
assert(R.new('nonsense', 16).c == R.COMPOUNDS.road, 'an unknown compound is a road tyre')
local warm = R.new('slick', 16, 0.3, 0.2, 20, 1)
near(warm.Ts, 92.5, 0.01, 'a tyre started warm sits in the middle of its window')

-- ---- Archard wear: depth = k * energy per area; twice the energy, twice the depth; harder compounds wear less
local function skid(compound, joules, ctx)
  local x = R.new(compound, 16, 0.305, 0.175, 20)
  R.addEnergy(x, 5, joules)
  R.wearStep(x, ctx or {}, cfg)
  return 8 - x.h[5] == 0 and x.c.h0 - x.h[5] or x.c.h0 - x.h[5], x
end
local d1 = skid('road', 100000)
local d2 = skid('road', 200000)
near(d2 / d1, 2, 0.001, 'wear is proportional to the energy')
assert(skid('slicksoft', 100000) > skid('slick', 100000) and skid('slick', 100000) > skid('road', 100000), 'soft slicks wear fastest')
assert(skid('road', 100000, { wet = true }) < d1 and skid('road', 100000, { surface = 'gravel' }) < d1 and skid('road', 100000, { surface = 'rock' }) > d1, 'wet and gravel wear less, rock more')
assert(skid('mud', 100000, { surface = 'rock' }) > skid('mud', 100000) * 1.9, 'chunking: mud tyres on rock wear twice as much')
assert(skid('road', 100000, { pressure = 150, pNom = 220 }) > d1 and skid('road', 100000, { pressure = 280, pNom = 220 }) > d1, 'under and over inflation both wear more')
local hotTyre = R.new('road', 16) hotTyre.Ts = 170 R.addEnergy(hotTyre, 5, 100000) R.wearStep(hotTyre, {}, cfg)
assert(8 - hotTyre.h[5] > 1.9 * d1, 'a tyre 60 C over its onset wears twice as fast')
local wornCold = R.new('road', 16) wornCold.Ts = 400 R.addEnergy(wornCold, 5, 100000) R.wearStep(wornCold, {}, cfg)
near(8 - wornCold.h[5], d1 * cfg.heatWearMax, 0.001, 'and the heat multiplier is capped')
-- nothing but rolling: the dead zone
assert(R.slipPower(0.2, 5000, 1, 0.3) == 0 and R.slipPower(1.3, 5000, 1, 0.3) == 5000, 'slip under the dead zone is not worn')
-- the global rate
local fast = R.defaults() fast.wearRate = 10
local x10, x1 = R.new('road', 16), R.new('road', 16)
R.addEnergy(x10, 5, 20000) R.addEnergy(x1, 5, 20000) R.wearStep(x10, {}, fast) R.wearStep(x1, {}, cfg)
near((8 - x10.h[5]) / (8 - x1.h[5]), 10, 0.001, 'the wear multiplier scales the time')

-- ---- the calibration target: 100 to 0 km/h locked on a 1500 kg car, ~190 kJ into one front tyre, ~1.5 mm of flat spot (research 2.2)
local lock = R.new('road', 16, 0.305, 0.175, 20)
-- the lock holds one patch of ~15,000 mm2, about one sector (both lanes); the stationary patch flashes hot (60 C over the tyre)
R.addEnergy(lock, 9, 95000) R.addEnergy(lock, 10, 95000) lock.flash[5] = 60
lock.Ts = 60 R.wearStep(lock, {}, cfg)
local w = R.worstFlat(lock)
assert(w > 1.0 and w < 3.0, 'a locked skid makes a flat spot of a millimetre or two: ' .. w)
-- the same energy spread over the whole ring does not
local roll = R.new('road', 16, 0.305, 0.175, 20)
for j = 1, 32 do R.addEnergy(roll, j, 190000 / 32) end
roll.Ts = 60 R.wearStep(roll, {}, cfg)
assert(R.worstFlat(roll) < 0.001, 'rolling wears the ring evenly: no flat spot')
assert(8 - roll.h[1] < 0.8, 'and not much, in one stop')
-- a flat spot is a shallow sector among deeper neighbours
local _, at = R.worstFlat(lock)
assert(at == 5, 'the flat spot is where the energy went: ' .. tostring(at))
assert(R.flatDepth(roll, 3) == 0, 'no flat depth on an even ring')
-- wrap-around: the ring is closed
local ring = R.new('road', 16) R.addEnergy(ring, 1, 150000) R.addEnergy(ring, 2, 150000) R.wearStep(ring, {}, cfg)
assert(R.flatDepth(ring, 1) > 0.5 and R.flatDepth(ring, 16) < 0.001 + 0.5 * 1.1, 'sector 1 is next to sector 16')
-- belts, cord and the blow-out
local worn = R.new('road', 16)
worn.h[5] = 0.1 R.addEnergy(worn, 5, 400000) R.wearStep(worn, {}, cfg)
assert(worn.h[5] < 0 and worn.h[5] >= -worn.c.margin - cfg.cordLimit, 'wear goes through the tread into the belts but not past the cord')
assert(R.stage(worn, cfg) == 5, 'belts showing is stage 5')
local gone = R.new('road', 16) gone.h[5] = -0.4 R.addEnergy(gone, 5, 2e6) R.wearStep(gone, {}, cfg)
assert(gone.blown and gone.h[5] == -gone.c.margin - cfg.cordLimit, 'the cord gives out: the tyre is gone')
assert(R.wearStep(gone, {}, cfg) == 0, 'a blown tyre wears no more')
R.clearEnergy(worn) assert(R.totalEnergy(worn) == 0, 'the energy is cleared after a tick')

-- ---- temperature
local function run(t0, seconds, ctx, dt)
  dt = dt or 0.05
  for _ = 1, math.floor(seconds / dt) do
    ctx.dt = dt
    R.tempStep(t0, ctx, cfg)
  end
end
-- a burnout: 37 kW into the tyre, a few seconds
local bt = R.new('road', 16, 0.305, 0.175, 20)
run(bt, 6, { power = 37000, v = 4, fz = 4000, ambient = 20 })
assert(bt.Ts > 150 and bt.Ts < 400, 'a burnout takes the thin surface layer past 150 C in six seconds: ' .. bt.Ts)
assert(bt.Tc < 60, 'while the carcass is still cool: ' .. bt.Tc)
assert(bt.Tc < bt.Ts - 30, 'the carcass lags the surface')
-- cooling at speed with no slip: the surface goes back toward the ambient, faster than standing
local cool1, cool2 = R.new('road', 16) cool1.Ts, cool2 = 120, R.new('road', 16)
cool2.Ts = 120
run(cool1, 20, { power = 0, v = 30, fz = 4000, ambient = 20 })
run(cool2, 20, { power = 0, v = 0, fz = 0, ambient = 20 })
assert(cool1.Ts < cool2.Ts and cool1.Ts < 90, 'moving air cools: ' .. cool1.Ts .. ' vs ' .. cool2.Ts)
local dryT, wetT = R.new('road', 16), R.new('road', 16)
dryT.Ts, wetT.Ts = 100, 100
run(dryT, 10, { power = 0, v = 20, fz = 4000, ambient = 15, wet = 0 })
run(wetT, 10, { power = 0, v = 20, fz = 4000, ambient = 15, wet = 1 })
assert(wetT.Ts < dryT.Ts - 3, 'rain cools the tread: ' .. wetT.Ts .. ' vs ' .. dryT.Ts)
-- steady driving settles above the ambient and is stable (no runaway)
local cruise = R.new('road', 16, 0.305, 0.175, 20)
run(cruise, 600, { power = 0, v = 30, fz = 4000, ambient = 20 })
assert(cruise.Ts > 20 and cruise.Ts < 70 and cruise.Tc > 20 and cruise.Tc < 90, 'a 10 minute cruise settles warm: ' .. cruise.Ts .. ' / ' .. cruise.Tc)
local a, b = cruise.Ts, cruise.Tc
run(cruise, 60, { power = 0, v = 30, fz = 4000, ambient = 20 })
near(cruise.Ts, a, 3, 'and stays there')
-- a hot brake warms the carcass
local brk = R.new('road', 16) local noBrk = R.new('road', 16)
run(brk, 60, { power = 0, v = 0, fz = 0, ambient = 20, brake = 300 })
run(noBrk, 60, { power = 0, v = 0, fz = 0, ambient = 20 })
assert(brk.Tc > noBrk.Tc + 5, 'hot brakes warm the tyre core')
-- the flash temperature: a locked sector flashes hot, decays when released
local fl = R.new('road', 16, 0.305, 0.175, 20)
R.addEnergy(fl, 5, 20000)
fl.E[5] = 20000
R.tempStep(fl, { dt = 0.1, power = 20000 / 0.1, v = 0, fz = 4000, ambient = 20 }, cfg)
assert(fl.flash[3] > 20 and fl.flash[3] > 5 * (fl.flash[4] or 0) and fl.flash[1] == 0, 'the sector that took the energy flashes: ' .. fl.flash[3])
R.clearEnergy(fl)
local peak = fl.flash[3]
for _ = 1, 100 do R.tempStep(fl, { dt = 0.05, power = 0, v = 0, fz = 4000, ambient = 20 }, cfg) end
assert(fl.flash[3] < peak * 0.2, 'and the flash falls away in seconds')
-- big time steps are limited, so the maths cannot blow up
local big = R.new('road', 16) R.tempStep(big, { dt = 5, power = 1e6, v = 0, fz = 0, ambient = 20 }, cfg)
assert(big.Ts < 200, 'dt is clamped')

-- ---- grip
local c = R.COMPOUNDS.slick
near(R.tempGrip(c, 95, cfg), 1, 1e-9, 'in the window, full grip')
assert(R.tempGrip(c, 20, cfg) < 0.8 and R.tempGrip(c, 20, cfg) >= c.grip20 - 1e-9, 'a cold slick gives its cold grip')
assert(R.tempGrip(c, -30, cfg) < R.tempGrip(c, 20, cfg) and R.tempGrip(c, -30, cfg) > 0.5, 'colder is worse, but not a cliff')
near(R.tempGrip(c, 115, cfg), 1 - 0.05, 1e-9, 'ten degrees over: a drop of 5%')
near(R.tempGrip(c, 400, cfg), 0.6, 1e-9, 'and a floor of 60%')
local gentle = R.defaults() gentle.hotGrip = 0
near(R.tempGrip(c, 140, gentle), 1, 1e-9, 'the overheat penalty can be switched off')
local cr = R.COMPOUNDS.road
near(R.wearGrip(cr, cr.h0, false), 1, 1e-9, 'new tread: full grip')
assert(R.wearGrip(cr, 0, false) == cr.dry0 and R.wearGrip(cr, 0, true) == cr.wet0, 'bald: dry grip stays, wet grip drops')
assert(R.wearGrip(cr, 0, true) < R.wearGrip(cr, 4, true) and R.wearGrip(cr, 4, true) < 1, 'wet grip falls as the tread goes')
local gt = R.new('road', 16, 0.305, 0.175, 60)
local s0, d0 = R.nodeGrip(gt, 5, false, cfg)
near(s0, 1, 1e-9, 'a warm new tyre: stock friction')
gt.h[5] = 0 local sb, db = R.nodeGrip(gt, 5, false, cfg)
assert(sb == cfg.beltGrip and db == cfg.beltSliding, 'belts: 0.55 static, 0.50 sliding')
gt.h[5], gt.h[6] = 6.5, 6.5
local sf = R.nodeGrip(gt, 5, false, cfg)
assert(sf < 1 and sf > 0.95, 'a node in a flat spot loses a little grip: ' .. sf)
local nf = R.defaults() nf.flat.enabled = false
near(R.nodeGrip(gt, 5, false, nf), R.wearGrip(R.COMPOUNDS.road, 6.5, false), 1e-9, 'flat-spot grip loss can be switched off: only the wear is left')

-- ---- looks
local fresh = R.new('road', 16)
assert(R.stage(fresh, cfg) == 0, 'new')
for _, tc in ipairs({ { 7.0, 1 }, { 5.0, 2 }, { 3.0, 3 }, { 1.6, 4 }, { 0.4, 4 }, { -0.1, 5 } }) do
  local x = R.new('road', 16) x.h[9] = tc[1]
  assert(R.stage(x, cfg) == tc[2], 'tread ' .. tc[1] .. ' mm is stage ' .. tc[2] .. ', got ' .. R.stage(x, cfg))
end

-- ---- the shake
near(R.shakeHz(27.8, 0.31), 14.3, 0.2, 'about 14 Hz at 100 km/h')
near(R.shakeForce(1.5), 375, 1e-9, '1.5 mm of flat spot pulls 375 N')

print('carSurfaceFx tyre rules: ok')
