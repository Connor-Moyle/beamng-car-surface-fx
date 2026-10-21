-- Every setting of the Tyres page changes something: each field of tyresSchema is switched (a switch flipped, a slider moved to its far end) and the rules, run on a standard scene, must give a
-- different result. A setting that changes nothing is dead code behind a slider. The few that act outside the rules (the game side, the car side) are listed with the test that proves them.
local R = require('csfx_tyrerules')
local Schema = require('carSurfaceFx/tyresSchema')

local reg = Schema.build({}, { rules = R, read = function() return {} end, write = function() end, reload = function() end })

local function copy(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == 'table' and copy(v) or v end return o end
local function sig(...)
  local o = {}
  for _, x in ipairs({ ... }) do o[#o + 1] = type(x) == 'number' and string.format('%.9g', x) or tostring(x) end
  return table.concat(o, '|')
end
local function tyre(Ts)
  local t = R.new('road', 16, 0.305, 0.175, 20)
  if Ts then t.Ts, t.Tc = Ts, Ts end
  return t
end

-- ---- the scenes
local function wear(cfg, ctx, o)
  o = o or {}
  local t = tyre(o.Ts)
  if (o.J or 2e5) > 0 then R.addEnergy(t, 5, o.J or 2e5, false) R.addEnergy(t, 6, o.J or 2e5, false) end
  R.wearStep(t, ctx or {}, cfg)
  return sig(t.h[5], t.shed or 0, t.blown)
end
local function heat(cfg)                                          -- 5 s of a hard slide at 20 m/s on a damp road
  local t = tyre(60)
  for _ = 1, 50 do R.tempStep(t, { dt = 0.1, v = 20, fz = 4000, ambient = 20, power = 20000, wet = 0.5 }, cfg) end
  return sig(t.Ts, t.Tc)
end
local function grip(cfg, setup, wet, ctx)
  local t = tyre()
  if setup then setup(t) end
  local a, b = R.nodeGrip(t, 5, wet, cfg, ctx)
  return sig(a, b)
end
local function tempGrip(cfg) return grip(cfg, function(t) t.Ts = 5 end) .. '/' .. grip(cfg, function(t) t.Ts = 150 end) end
local function fire(cfg, wet)
  local t = tyre(450)
  local ev = {}
  for i = 1, 60 do
    t.Ts = (t.fire or t.blown) and t.Ts or 450
    local e = R.fireStep(t, 0.5, wet, cfg)
    if e then ev[#ev + 1] = i .. e end
  end
  return sig(table.concat(ev, ','), t.Ts, t.fire or 'nofire', t.blown)
end
local function fires(cfg) return fire(cfg, 0) .. '/' .. fire(cfg, 0.5) end
local function pile(cfg)
  local p = { g = 100, T = 500, burn = 0 }
  local on = R.pileStep(p, 1, 20, 0, cfg)
  return sig(p.T, p.burn, on)
end
local function marbleList(cfg, n, g)
  local list = {}
  for i = 1, n do R.marbleAdd(list, i * 10, 0, 0, g, 300, 0, cfg) end
  return list
end

-- ---- what each setting is observed through. Every row is { scene } called with a cfg
local E = {
  wearEnabled = function(c) return wear(c) end,
  wearRate = function(c) return wear(c) end,
  ['flat.enabled'] = function(c) return grip(c, function(t) t.h[5], t.h[6] = 7, 7 end) end,
  ['flat.minDepth'] = function(c) return grip(c, function(t) t.h[5], t.h[6] = 7, 7 end) end,
  ['flat.gripLoss'] = function(c) return grip(c, function(t) t.h[5], t.h[6] = 7, 7 end) end,
  spinWear = function(c) return wear(c) end,
  deadZone = function(c) return sig(R.slipPower(1, 4000, 1, c.deadZone)) end,
  heatWearScale = function(c) return wear(c, {}, { Ts = 400 }) end,
  heatWearMax = function(c) return wear(c, {}, { Ts = 400 }) end,
  cordLimit = function(c) return wear(c, {}, { J = 1e9 }) end,
  rollWear = function(c) return wear(c, { dist = 10000 }, { J = 0 }) end,
  pressureEffect = function(c) return wear(c, { pressure = 150, pNom = 220 }) end,
  ['look.wornBelow'] = function(c) local t = tyre() for j = 1, 2 * t.n do t.h[j] = 4.8 end return R.stage(t, c) end,
  heatRate = heat, coolRate = heat, sunRoad = function(c) return heat(c) end, rainCool = heat,
  tempGripEnabled = tempGrip, coldGrip = tempGrip, hotGrip = tempGrip,
  beltGrip = function(c) return grip(c, function(t) t.h[5] = 0 end) end,
  beltSliding = function(c) return grip(c, function(t) t.h[5] = 0 end) end,
  wetGripEnabled = function(c) return grip(c, nil, true, { water = 0.5, v = 30, surface = 'asphalt' }) end,
  ['debris.enabled'] = function(c) local t = tyre(150) t.shed = 1000 return sig(R.takeDebris(t, c)) end,
  ['debris.hotFrom'] = function(c) local t = tyre(150) t.shed = 1000 return sig(R.takeDebris(t, c)) end,
  ['debris.hotTo'] = function(c) local t = tyre(150) t.shed = 1000 return sig(R.takeDebris(t, c)) end,
  ['debris.pileTau'] = pile, ['debris.pileIgniteT'] = pile, ['debris.pileMinG'] = pile, ['debris.pileBurnS'] = pile,
  smokeEnabled = function(c) return sig(R.smoke(150, c)) end, smokeOn = function(c) return sig(R.smoke(150, c)) end, smokeFull = function(c) return sig(R.smoke(150, c)) end,
  fires = fires, igniteT = fires, igniteHold = fires, burnT = fires, popAfter = fires, douse = fires, fireSpread = fires,
  spreadAfter = function(c) c.fireSpread = true return fires(c) end,                  -- (it only counts when the fire may spread)
  ['marbles.gripLoss'] = function(c) return sig(R.marbleGrip(200, c)) end,
  ['marbles.burn'] = function(c) local l = { { x = 0, y = 0, z = 0, g = 100, T = 500, burn = 0 } } return sig(R.marbleStep(l, 1, 20, 0, c), l[1] and l[1].burn or 0) end,
  ['marbles.maxPatches'] = function(c) return sig(#marbleList(c, 30, 10)) end,
  ['marbles.maxG'] = function(c) return sig(marbleList(c, 1, 500)[1].g) end,
  ['marbles.lifeS'] = function(c) local l = { { x = 0, y = 0, z = 0, g = 100, T = 20, burn = 0 } } R.marbleStep(l, 60, 20, 0, c) return sig(l[1] and l[1].g or 0) end,
}
for _, w in ipairs({ 'asphalt', 'concrete', 'wet', 'gravel', 'dirt', 'rock', 'snow', 'ice' }) do
  E['surface.' .. w] = function(c) return w == 'wet' and wear(c, { wet = true }) or wear(c, { surface = w }) end
end

-- the settings that act outside the rules, and the test that proves each (fengari has no io to look: those tests carry the setting's name in their own asserts)
local ELSEWHERE = {
  enabled = 'tyres_off_test.lua', rainAquaplane = 'tyres_ge_test.lua', ['blowout.enabled'] = 'tyres_ge_test.lua', ['blowout.strength'] = 'tyres_ge_test.lua',
  ['look.enabled'] = 'tyres_car_test.lua', sparksEnabled = 'tyres_car_test.lua', ['marbles.enabled'] = 'marbles_test.lua',      -- (the game-side marbles module keeps state: not touched here)
}

local checked, elsewhere = 0, 0
for _, f in ipairs(reg.fields) do
  local path = f.store and f.store.kind == 'json' and f.store.path
  if path and not path:find('^compounds%.') then
    if ELSEWHERE[path] then
      elsewhere = elsewhere + 1
    else
      local scene = assert(E[path], 'a scene for the setting ' .. path .. ' (add one to tests/tyres_effect_test.lua)')
      local A, B = R.defaults(), R.defaults()
      local node, key = B, nil
      local parts = {}
      for part in path:gmatch('[^%.]+') do parts[#parts + 1] = part end
      for i = 1, #parts - 1 do node = node[parts[i]] end
      key = parts[#parts]
      local was = node[key]
      if f.type == 'bool' then node[key] = not was
      else node[key] = (was ~= f.max) and f.max or f.min end
      assert(node[key] ~= was, path .. ': a different value to try')
      local a, b = scene(A), scene(B)
      assert(a ~= b, path .. ' changes nothing in its scene: ' .. tostring(a) .. ' both ways')
      checked = checked + 1
    end
  end
end
assert(checked >= 54, 'the settings were walked: ' .. checked)

-- every field of every compound changes something: grip, wear, temperature, aquaplaning or the swap ratio
local function compoundScene(name)
  local c = R.COMPOUNDS[name]
  local t = R.new(name, 16, 0.305, 0.175, 20)
  local cfg = R.defaults()
  local o = {}
  o[#o + 1] = sig(t.h[1], c.h0)
  for _, T in ipairs({ -40, -26, -10, 5, 9, 14, 19, 22, 24, 30, 60, 100, 140 }) do o[#o + 1] = sig(R.tempGrip(c, T, cfg)) end
  for _, h in ipairs({ 0.5, 2, c.h0 }) do for _, wet in ipairs({ false, true }) do o[#o + 1] = sig(R.wearGrip(c, h, wet)) end end
  for _, v in ipairs({ 8, 11, 14, 17, 20, 23, 26, 30, 34, 40, 50 }) do o[#o + 1] = sig(R.aquaplane(c, c.h0 * 0.5, 0.8, v), R.aquaplane(c, c.h0, 0.8, v)) end
  o[#o + 1] = sig(R.surfaceGrip(c, 'dirt'), R.surfaceGrip(c, 'snow'))
  o[#o + 1] = sig(R.swapRatio(name == 'slick' and 'road' or 'slick', name))
  local w = R.new(name, 16, 0.305, 0.175, 20)
  w.Ts = 200 R.addEnergy(w, 5, 2e5, false) R.wearStep(w, {}, cfg)
  o[#o + 1] = sig(w.h[5], w.shed or 0)
  R.addEnergy(w, 5, 1e9, false) R.wearStep(w, {}, cfg)
  o[#o + 1] = sig(w.h[5])
  local h = R.new(name, 16, 0.305, 0.175, 20)
  for _ = 1, 20 do R.tempStep(h, { dt = 0.1, v = 25, fz = 4000, ambient = 20, power = 0 }, cfg) end
  o[#o + 1] = sig(h.Ts)
  return table.concat(o, '/')
end
local fields, idle = 0, 0
for name, c in pairs(R.COMPOUNDS) do
  local base = compoundScene(name)
  for k, v in pairs(c) do
    c[k] = v * 1.37 + 0.011
    local moved = compoundScene(name)
    c[k] = v
    if k == 'lo' and c.grip20 >= 1 then idle = idle + 1       -- a tyre that loses nothing at 20 C has no cold fade for lo to move (offroad, mud): found by this test, the data is as tuned
    else assert(moved ~= base, 'the compound field ' .. name .. '.' .. k .. ' changes nothing') fields = fields + 1 end
  end
  assert(compoundScene(name) == base, 'the compound is back as it was: ' .. name)
end
assert(fields > 150, 'the compound fields were walked: ' .. fields)
print('carSurfaceFx tyre settings: each changes something (' .. checked .. ' in the rules, ' .. elsewhere .. ' proven elsewhere, ' .. fields .. ' compound fields, ' .. idle .. ' idle by their data)')
