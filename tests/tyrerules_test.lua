-- Tyre rules (tyrerules.lua): sectors, Archard wear, flat spot from a locked skid, temperature heat and cool, the grip curve and the looks. No game calls.
local R = require('csfx_tyrerules')
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

-- ---- the calibration target (62, live test): a 1 s lock from 46 km/h (~64 kJ) leaves 0.1 to 0.3 mm, 100 to 0 km/h locked (~190 kJ into one front tyre) about a millimetre
local lock = R.new('road', 16, 0.305, 0.175, 20)
-- the lock holds one patch of ~15,000 mm2, about one sector (both lanes); the stationary patch flashes hot (60 C over the tyre)
R.addEnergy(lock, 9, 95000, true) R.addEnergy(lock, 10, 95000, true) lock.flash[5] = 60
lock.Ts = 150 R.wearStep(lock, {}, cfg)               -- (a long skid heats the tyre: about 150 C by the end)
local w = R.worstFlat(lock)
assert(w > 0.3 and w < 1.5, 'a long locked skid makes a flat spot of about a millimetre: ' .. w)
local short = R.new('road', 16, 0.305, 0.175, 20)
R.addEnergy(short, 9, 32000, true) R.addEnergy(short, 10, 32000, true) short.Ts = 40 short.flash[5] = 30 R.wearStep(short, {}, cfg)
assert(R.worstFlat(short) > 0.05 and R.worstFlat(short) < 0.3, 'and a 1 s lock from 46 km/h a flat spot of 0.1 to 0.3 mm: ' .. R.worstFlat(short))
-- the same energy spread over the whole ring does not
local roll = R.new('road', 16, 0.305, 0.175, 20)
for j = 1, 32 do R.addEnergy(roll, j, 190000 / 32) end
roll.Ts = 60 R.wearStep(roll, {}, cfg)
assert(R.worstFlat(roll) < 0.001, 'rolling wears the ring evenly: no flat spot')
assert(8 - roll.h[1] < 0.8, 'and not much, in one stop')
-- three kinds of wear: a locked wheel's sliding stays low, wheelspin and cornering are spinWear times faster, and rolling micro-slip below the dead zone wears nothing
local wl, ws, wn = R.new('road', 16), R.new('road', 16), R.new('road', 16)
R.addEnergy(wl, 5, 50000, true) R.addEnergy(ws, 5, 50000, false)
R.addEnergy(wn, 5, R.slipPower(0.1, 4000, 1, cfg.deadZone) * 10)
for _, x in ipairs({ wl, ws, wn }) do R.wearStep(x, {}, cfg) end
near((8 - ws.h[5]) / (8 - wl.h[5]), cfg.spinWear, 1e-9, 'wheelspin wears spinWear times faster than a locked slide')
assert(cfg.spinWear == 4 and wn.h[5] == 8, 'rolling micro-slip wears nothing')
-- a full burnout reaches the belts in about two minutes (live test: 0.1 mm/s on the worst slot): 40 kW into a few slots, the surface hot
local burn = R.new('road', 16, 0.305, 0.175, 20) burn.Ts = 150
local secs = 0
while burn.h[1] > 0 and secs < 600 do
  for j = 1, 6 do R.addEnergy(burn, j, 40000 / 6) end            -- (the slip power lands on a few slots of the ring, not evenly: the worst slot decides)
  R.wearStep(burn, {}, cfg) R.clearEnergy(burn) secs = secs + 1
end
assert(secs > 60 and secs < 240, 'a full burnout wears an 8 mm road tyre to the belts in one to four minutes: ' .. secs .. ' s')
-- a flat spot is a shallow sector among deeper neighbours
local _, at = R.worstFlat(lock)
assert(at == 5, 'the flat spot is where the energy went: ' .. tostring(at))
assert(R.flatDepth(roll, 3) == 0, 'no flat depth on an even ring')
-- wrap-around: the ring is closed
local ring = R.new('road', 16) R.addEnergy(ring, 1, 500000, true) R.addEnergy(ring, 2, 500000, true) R.wearStep(ring, {}, cfg)
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

-- ---- wet performance by compound
local C = R.COMPOUNDS
local function wg(name, wet) return R.wearGrip(C[name], C[name].h0, wet) end
assert(wg('slick', 1) < 0.6 * wg('fullwet', 1), 'a slick on wet is far below a rain tyre: ' .. wg('slick', 1) .. ' vs ' .. wg('fullwet', 1))
assert(wg('road', 1) > wg('slick', 1) and wg('road', 1) < wg('intermediate', 1) and wg('intermediate', 1) < wg('fullwet', 1), 'road sits between slick and rain tyres')
assert(wg('fullwet', 0) < wg('road', 0) and wg('intermediate', 0) < wg('road', 0), 'rain tyres give up grip on a dry road')
near(wg('road', 0.5), (wg('road', 0) + wg('road', 1)) / 2, 1e-9, 'half wet is halfway')
assert(R.wearGrip(C.road, 2, 1) < R.wearGrip(C.road, 8, 1), 'worn tread is worse in the wet')
-- aquaplaning: a slick goes first, a bald tyre earlier than a new one, a dry puddle-free road never
assert(R.aquaplane(C.slick, 3, 0, 40) == 1, 'no water, no aquaplaning')
assert(R.aquaplane(C.slick, 3, 1, 25) < R.aquaplane(C.fullwet, 9, 1, 25), 'at 90 km/h in a puddle the slick floats first')
assert(R.aquaplane(C.road, 2, 1, 20) < R.aquaplane(C.road, 8, 1, 20), 'less tread aquaplanes at lower speed')
near(R.aquaplane(C.road, 8, 1, 5), 1, 1e-9, 'slow through a puddle is fine')
-- loose ground and snow
assert(R.surfaceGrip(C.mud, 'mud') > R.surfaceGrip(C.slick, 'mud'), 'mud tyres beat slicks in mud')
assert(R.surfaceGrip(C.winter, 'snow') > R.surfaceGrip(C.road, 'snow'), 'winter tyres beat road tyres on snow')
near(R.surfaceGrip(C.road, 'asphalt'), 1, 1e-9, 'tarmac: no change')
-- a node in a puddle: the slick loses more than the rain tyre
local sl, fwt = R.new('slick', 16, 0.3, 0.2, 80), R.new('fullwet', 16, 0.3, 0.2, 40)
local gs = R.nodeGrip(sl, 5, 1, cfg, { water = 1, v = 30 })
local gf = R.nodeGrip(fwt, 5, 1, cfg, { water = 1, v = 30 })
assert(gs < 0.5 * gf, 'slick vs rain tyre in a puddle at 108 km/h: ' .. gs .. ' vs ' .. gf)
-- a rain tyre on a dry road overheats: grip falls at a temperature a road tyre handles, and wears faster
assert(R.tempGrip(C.fullwet, 80, cfg) < R.tempGrip(C.road, 80, cfg), 'a rain tyre at 80 C is past its window')
assert(R.heatWear(C.fullwet, 100, cfg) > R.heatWear(C.road, 100, cfg), 'and wears faster there')
-- rain cools a slick: same power, wet vs dry
local function run(wet) local x = R.new('slick', 16, 0.3, 0.2, 20, 1) for _ = 1, 600 do R.tempStep(x, { dt = 0.05, power = 8000, v = 30, fz = 4000, ambient = 20, wet = wet }, cfg) end return x.Ts end
assert(run(1) < run(0) - 5, 'rain cools the tyre: ' .. run(1) .. ' vs ' .. run(0))

-- ---- fitting another compound, saving
near(R.swapRatio('road', 'slick'), 1.2, 1e-9, 'a slick on a road jbeam: +20%')
near(R.swapRatio('slick', 'road') * R.swapRatio('road', 'slick'), 1, 1e-9, 'and back')
near(R.swapRatio('road', 'road'), 1, 1e-9, 'same class: nothing')
local sv = R.new('road', 16) sv.h[3] = 4.123456 sv.blown = true
local blob = R.snapshot(sv)
assert(blob.h[3] == 4.12 and blob.compound == 'road' and blob.blown, 'snapshot rounds to 0.01 mm')
local sr = R.new('road', 16) assert(R.restore(sr, blob) and sr.h[3] == 4.12 and sr.blown, 'restore round-trips')
assert(not R.restore(R.new('road', 20), blob), 'a blob from another ring size is refused')

-- ---- ground names
for _, c in ipairs({ { 'ASPHALT', 'asphalt' }, { 'asphalt_wet', 'asphalt' }, { 'DIRT_DUSTY', 'dirt' }, { 'GRAVEL', 'gravel' }, { 'MUD', 'mud' }, { 'SAND', 'sand' }, { 'GRASS2', 'grass' }, { 'SNOW_ICE', 'ice' },
  { 'snowy_road', 'snow' }, { 'ROCK_SMOOTH', 'rock' }, { 'concrete', 'concrete' }, { 'COBBLESTONE', 'asphalt' } }) do
  assert(R.surfaceOfGround(c[1]) == c[2], c[1] .. ' is ' .. c[2] .. ', got ' .. tostring(R.surfaceOfGround(c[1])))
end
assert(R.surfaceOfGround('METAL') == nil and R.surfaceOfGround(nil) == nil, 'unknown ground: nil (no change)')
local wm, wd = R.new('road', 16), R.new('road', 16)
wm.E[3], wd.E[3] = 100, 100
R.wearStep(wm, { surface = 'mud' }, cfg) R.wearStep(wd, { surface = 'dirt' }, cfg)
near(wm.h[3], wd.h[3], 1e-12, 'mud wears like dirt')
assert(R.surfaceGrip(R.COMPOUNDS.offroad, 'grass') > 1, 'grass is loose ground for the grip')

-- ---- blowout damage
assert(cfg.blowout.enabled == false and cfg.blowout.maxForce == 3000, 'unproven: off by default, 3000 N')
assert(R.blowoutHit(30, 1, 0, cfg) == nil, 'off by default: never')
cfg = R.defaults() cfg.blowout.enabled = true
assert(R.blowoutHit(30, 1, 0.99, cfg) == nil and R.blowoutHit(30, 1, 0.5, cfg), 'a roll above the chance misses, below it hits')
assert(R.blowoutHit(0, 1, 0.5, cfg) == nil and R.blowoutHit(30, 1, 0.5, cfg) ~= nil, 'a stationary tyre rarely hurts the panels')
local hs, hf = R.blowoutHit(5, 1, 0.01, cfg), R.blowoutHit(30, 1, 0.01, cfg)
assert(hf.force > hs.force and hf.n >= hs.n, 'faster blows harder')
assert(R.blowoutHit(30, 0.3, 0.01, cfg).force < hf.force, 'a flat-ish tyre has less burst')
local big = R.defaults() big.blowout.enabled = true big.blowout.strength = 100
assert(R.blowoutHit(40, 1.5, 0.01, big).force <= big.blowout.maxForce, 'the force is capped')
local off = R.defaults()
assert(R.blowoutHit(30, 1, 0, off) == nil, 'switched off: never')
local bn = { { cid = 1, x = 0.1, y = 0, z = 0 }, { cid = 2, x = 0.3, y = 0, z = 0 }, { cid = 3, x = 2, y = 0, z = 0 }, { cid = 4, x = 0.2, y = 0.1, z = 0 }, { cid = 9, x = 0.05, y = 0, z = 0 } }
local tg = R.blowoutTargets(bn, { x = 0, y = 0, z = 0 }, 0.5, { [9] = true }, 2)
assert(#tg == 2 and tg[1].cid == 1 and tg[2].cid == 4, 'nearest first, the wheel own node 9 and the far node 3 are left out')
near(tg[1].dx, 1, 1e-9, 'directed away from the wheel')
-- only plain body panels are targets
local bad = { { cid = 20, x = 0.1, y = 0, z = 0, fixed = true }, { cid = 21, x = 0.1, y = 0, z = 0, couplerTag = 'tow' }, { cid = 22, x = 0.1, y = 0, z = 0, group = 'fl_hub' },
  { cid = 23, x = 0.1, y = 0, z = 0, group = { 'body', 'frontsusp' } }, { cid = 24, x = 0.1, y = 0, z = 0, special = true }, { cid = 25, x = 0.1, y = 0, z = 0, wheel = true }, { cid = 26, x = 0.1, y = 0, z = 0, group = 'fender_FL' } }
local tb = R.blowoutTargets(bad, { x = 0, y = 0, z = 0 }, 0.5, {}, 10)
assert(#tb == 1 and tb[1].cid == 26, 'fixed, coupler, hub, suspension, special and wheel nodes are rejected; the fender stays: ' .. #tb)
-- the force never exceeds maxForce, over a sweep
for sp = 0, 80, 5 do for pr = 0, 1.5, 0.25 do for _, st in ipairs({ 0.5, 1, 5, 100 }) do
  local c2 = R.defaults() c2.blowout.enabled = true c2.blowout.strength = st
  local h = R.blowoutHit(sp, pr, 0, c2)
  assert(not h or h.force <= c2.blowout.maxForce, 'force within the cap') end end end

-- ---- debris, smoke, fire
local d = R.new('road', 16) d.Ts = 60 d.shed = 1000
local gCool = R.takeDebris(d, cfg)
d.Ts = 250 d.shed = 1000
local gHot, tHot = R.takeDebris(d, cfg)
assert(gHot > gCool and d.shed == 0 and tHot == 250, 'hot rubber throws more debris: ' .. gCool .. ' ' .. gHot)
near(R.smoke(90, cfg), 0, 1e-9, 'no smoke at 90') near(R.smoke(135, cfg), 0.5, 1e-9, 'half smoke at 135') near(R.smoke(300, cfg), 1, 1e-9, 'full smoke')
local pile = { g = 50, T = 400 }
assert(R.pileStep(pile, 0.1, 20, 0, cfg), 'a hot pile of 50 g catches')
local cold = { g = 50, T = 100 } assert(not R.pileStep(cold, 0.1, 20, 0, cfg), 'a cool pile does not')
local small = { g = 5, T = 400 } assert(not R.pileStep(small, 0.1, 20, 0, cfg), 'a few crumbs do not')
local pl = { g = 50, T = 400 } for _ = 1, 400 do R.pileStep(pl, 0.1, 20, 0, cfg) end
assert((pl.burn or 0) <= 0, 'the pile burns out')
local ft = R.new('road', 16) ft.Ts = 500
assert(R.fireStep(ft, 2, 0, cfg) == nil and R.fireStep(ft, 2.5, 0, cfg) == 'ignite' and ft.fire, 'sustained 500 C ignites after 4 s (igniteT 420, hold 4)')
local fl = R.new('road', 16) fl.Ts = 500 R.fireStep(fl, 1, 0, cfg) fl.Ts = 100 R.fireStep(fl, 1, 0, cfg)
assert(not fl.fire and fl.hold == 0, 'a dip resets the hold')
local pop for _ = 1, 200 do pop = R.fireStep(ft, 0.1, 0, cfg) or pop end
assert(pop == 'pop' and ft.blown and not ft.fire, 'a tyre that burns long enough pops')
assert(cfg.fireSpread == false, 'spread to the car is off by default (unproven)')
local cs = R.defaults() cs.fireSpread = true
local sp = R.new('road', 16) sp.Ts = 500 R.fireStep(sp, 5, 0, cs)
local ev for _ = 1, 50 do ev = R.fireStep(sp, 0.1, 0, cs) or ev if ev then break end end
assert(ev == 'spread', 'the fire reaches the car after spreadAfter s: ' .. tostring(ev))
local nc = R.defaults() nc.fireSpread = false
local ns = R.new('road', 16) ns.Ts = 500 R.fireStep(ns, 5, 0, nc) local nev for _ = 1, 50 do nev = R.fireStep(ns, 0.1, 0, nc) or nev end
assert(nev ~= 'spread', 'no spread when the option is off')
local nf2 = R.defaults() nf2.fires = false
local no = R.new('road', 16) no.Ts = 500 assert(R.fireStep(no, 5, 0, nf2) == nil and not no.fire, 'no tyre fires when switched off')
local fw = R.new('road', 16) fw.Ts = 500 R.fireStep(fw, 5, 0, cfg)
local out for _ = 1, 100 do out = R.fireStep(fw, 0.1, 1, cfg) or out if out then break end end
assert(out == 'out', 'rain puts it out: ' .. tostring(out))

-- ---- the switches and the look stages from the settings
local nd = R.defaults() nd.debris.enabled = false
local dd = R.new('road', 16) dd.Ts = 250 dd.shed = 1000
local gOff = R.takeDebris(dd, nd)
assert(gOff == 0 and dd.shed == 0, 'rubber debris can be switched off')
local lk = R.defaults() lk.look.wornBelow = 0.8
local lx = R.new('road', 16) lx.h[9] = 8 * 0.75             -- 75% left: not worn by default (stage 1), worn with the limit at 0.8 (stage 3)
assert(R.stage(lx, cfg) == 1 and R.stage(lx, lk) == 3, 'the worn limit follows the setting: ' .. R.stage(lx, lk))
local lw = R.defaults() lw.look.wornBelow = 0.2
local ly = R.new('road', 16) ly.h[9] = 8 * 0.4
assert(R.stage(ly, cfg) == 3 and R.stage(ly, lw) == 2, 'a lower limit keeps a tyre looking not worn for longer')
local lb = R.new('road', 16) lb.h[9] = 0.4
assert(R.stage(lb, cfg) >= 4 and R.stage(lb, lw) >= 4, 'under half a millimetre is always worn out')
assert(R.defaults().look.wornBelow == 0.5 and R.defaults().look.enabled == true, 'the look defaults')

-- ---- wear, temperature and wet grip: each switch on its own
local sw = R.defaults() sw.wearEnabled = false
local sx = R.new('road', 16) sx.E[1] = 5000 sx.EL[1] = 5000
local h0 = sx.h[1]
R.wearStep(sx, { surface = 'asphalt', pressure = 1, pNom = 1 }, sw)
assert(sx.h[1] == h0, 'wear off: the tread stays')
local st = R.defaults() st.tempGripEnabled = false
assert(R.tempGrip(R.COMPOUNDS.road, -10, st) == 1 and R.tempGrip(R.COMPOUNDS.road, 150, st) == 1 and R.tempGrip(R.COMPOUNDS.road, -10, cfg) < 1, 'temperature switch off: grip is the same at any temperature')
local sg = R.defaults() sg.wetGripEnabled = false
local tg = R.new('road', 16)
local dryF = R.nodeGrip(tg, 1, false, cfg, { surface = 'asphalt', water = 0, v = 20 })
local wetOn = R.nodeGrip(tg, 1, true, cfg, { surface = 'asphalt', water = 1, v = 40 })
local wetOff = R.nodeGrip(tg, 1, true, sg, { surface = 'asphalt', water = 1, v = 40 })
assert(wetOn < dryF and math.abs(wetOff - R.nodeGrip(tg, 1, false, sg, { surface = 'asphalt', water = 0, v = 40 })) < 1e-9, 'wet grip off: wet is as dry (also no aquaplaning)')

print('carSurfaceFx tyre rules: ok')
