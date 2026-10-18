-- Tests of mod/lua/ge/extensions/carSurfaceFx/rules.lua (run by tools/luatest.js).
local R = require('carSurfaceFx/rules')
local n = 0
local function eq(a, b, what) n = n + 1 if a ~= b then error(what .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end end

eq(R.level(0, 0), 0, 'dry')
eq(R.level(0.1, 0), 1, 'damp')
eq(R.level(0.5, 0), 3, 'wet')
eq(R.level(0.9, 0), 5, 'soaked')
eq(R.level(0.38, 3), 3, 'hysteresis holds rung 3 just under its threshold')
eq(R.level(0.30, 3), 2, 'falls to rung 2')
eq(R.level(0.03, 1), 1, 'hysteresis holds rung 1')
eq(R.level(0.0, 5), 0, 'dries to 0')

eq(R.target(0.6, 9999), 0.6, 'Street Legal wetness wins')
eq(R.target(nil, 400), 0.5, 'drops count')
eq(R.target(nil, nil), 0, 'no rain object')
eq(R.target(nil, 5000), 1, 'clamped')

eq(R.wetStep(0, 1, 5), 0.2, 'soaks in at 1/25 per second')
eq(R.wetStep(0.9, 0, 30), 0.8, 'dries at 1/300 per second')
eq(R.wetStep(0.99, 1, 60), 1, 'does not overshoot')

eq(R.isPaintStage({ colorPaletteMap = '/a.png' }), true, 'palette is paint')
eq(R.isPaintStage({ clearCoatFactor = '1' }), false, 'a clear coat alone is not paint')

local body = { name = 'vivace_main', version = '1.5', translucent = '0', meshes = 35, stages = { [0] = { colorPaletteMap = '/p.png' }, [1] = {} } }
local wheel = { name = 'wheel', version = '1.5', translucent = '0', meshes = 4, stages = { [0] = { colorPaletteMap = '/p.png' } } }
local glass = { name = 'glass', version = '1.5', translucent = '1', meshes = 6, stages = { [0] = { colorPaletteMap = '/p.png' } } }
local old = { name = 'old', version = '1', translucent = '0', meshes = 50, stages = { [0] = { colorPaletteMap = '/p.png' } } }
local p = R.paintNames({ body, wheel, glass, old })
eq(p.vivace_main, true, 'body is paint')
eq(p.wheel, nil, 'wheel is not')
eq(p.glass, nil, 'glass is not')
eq(p.old, nil, 'v0 material is not')
-- a carbon roof: clear-coated, translucent, few meshes: it gets wet like the rest of the body
local roof = { name = 'car_cf', version = '1.5', translucent = 'true', meshes = 2, stages = { [0] = { clearCoatFactor = '0.5' } } }
local plain = { name = 'car_plastic', version = '1.5', translucent = '0', meshes = 5, stages = { [0] = {} } }
local with = R.paintNames({ body, wheel, glass, old, roof, plain })
assert(with.car_cf and not with.car_plastic, 'a clear-coated translucent roof panel is body paint too, a plain material is not')
-- the rest of the outside: trim, bumpers and wheels yes; interior, seats, screens, glass, translucent no
local trim = R.trimNames({ body, { name = 'car_bumper', version = '1.5', translucent = '0', meshes = 4, stages = { [0] = {} } }, { name = 'car_wheel', version = '1.5', translucent = '0', meshes = 4, stages = { [0] = {} } },
  { name = 'car_interior', version = '1.5', translucent = '0', meshes = 40, stages = { [0] = {} } }, { name = 'car_seats', version = '1.5', translucent = '0', meshes = 8, stages = { [0] = {} } },
  { name = 'car_logo', version = '1.5', translucent = 'true', meshes = 1, stages = { [0] = {} } }, { name = 'car_glass', version = '1.5', translucent = 'true', meshes = 5, stages = { [0] = {} } } }, R.paintNames({ body, wheel, glass, old }))
assert(trim.car_bumper and trim.car_wheel and not trim.car_interior and not trim.car_seats and not trim.car_logo and not trim.car_glass and not trim.car_body, 'trim: the outside without paint, glass and the inside')
-- lamps are never touched: by name, and by an emissive setting; and a lamp is not glass
assert(R.isLampName('etk800_taillight_lens') and R.isLampName('x_indicator') and R.isLampName('pickup_reverse') and not R.isLampName('vivace_glass'), 'lamp names')
assert(not R.isGlassName('car_glass_headlight') and R.isGlassName('car_glass'), 'a glass-named lamp is not glass')
assert(R.isEmissive({ [0] = { emissiveFactor = '0.5 0.5 0.5' } }) and R.isEmissive({ [0] = { glow = '1' } }) and not R.isEmissive({ [0] = { emissiveFactor = '0 0 0' } }), 'emissive materials')
local lampRoof = { name = 'car_trimlamp', version = '1.5', translucent = 'true', meshes = 2, stages = { [0] = { clearCoatFactor = '0.5' } } }
local glowing = { name = 'car_plasticx', version = '1.5', translucent = '0', meshes = 5, stages = { [0] = { emissiveFactor = '1 1 1' } } }
assert(not R.paintNames({ body, lampRoof }).car_trimlamp and not R.trimNames({ body, glowing }, R.paintNames({ body })).car_plasticx, 'a lamp or a glowing material never counts as body or trim')
assert(R.outsideMode == 'emissive', 'the outside glass never replaces the tint map by default: the glass keeps its own colour')
local nopal = R.paintNames({ { name = 'a', version = '1.5', translucent = '0', meshes = 3, stages = { [0] = {} } }, { name = 'b', version = '1.5', translucent = '0', meshes = 9, stages = { [0] = {} } } })
eq(nopal.b, true, 'no palette: the biggest')

local w = R.wetFields({ baseColorFactor = '1 0.5 0 1', roughnessFactor = '0.8' }, 5)
eq(w.baseColorFactor, '0.7500 0.3750 0.0000 1.0000', 'darker')
eq(w.roughnessFactor, '0.4000', 'glossier')
eq(w.detailNormalMap, '/art/surfacefx/droplets5.normal.png', 'the rungs own bead map')
eq(w.detailScale, R.beadScale, 'detail scale set')
local keep = R.wetFields({ detailMap = '/x.png' }, 1)
eq(keep.detailNormalMap, nil, 'a stage with another detail map is left alone')
local peel = R.wetFields({ detailNormalMap = '/orange_peel.png', detailScale = '128 64' }, 1)
eq(peel.detailNormalMap, '/art/surfacefx/droplets1.normal.png', 'beads replace the orange peel while wet')

-- glass
eq(R.isGlassName('vivace_glass'), true, 'glass')
eq(R.isGlassName('vivace_glass_dmg'), false, 'damaged glass is a different material')
eq(R.isGlassName('vivace_main'), false, 'paint')
eq(R.glassTag('vivace_glass'), '@csfx_vivace_glass', 'one canvas name per window material')
eq(R.glassFields({ baseColorMap = 'vehicles/vivace/vivace_glass_b.color.png' }, '@csfx_x').baseColorMap, '@csfx_x', 'the canvas replaces the tint map')
eq(R.glassFields({}, '@csfx_x').baseColorMap, nil, 'glass without a tint map is left alone')
eq(R.glassMode('vivace_glass_int'), 'emissive', 'inside glass uses its emissive map')
eq(R.glassMode('vivace_glass'), 'emissive', 'outside glass keeps its own colour and takes only glints (never a darker tint)')
R.outsideMode = 'color'
eq(R.glassMode('vivace_glass'), 'color', 'the outside mode can be switched')
R.outsideMode = 'emissive'
local inside = R.glassFields({ baseColorMap = '/b.png' }, '@csfx_x', 'emissive')
eq(inside.emissiveMap, '@csfx_x', 'the canvas lights the inside glass')
eq(inside.baseColorMap, nil, 'and leaves the tint')
eq(inside.emissiveFactor ~= nil, true, 'with a brightness')
eq(R.isGlassName('vivace_glass_invisible'), false, 'invisible glass')
eq(R.isGlassName('glass_cracks'), false, 'cracks')

-- dirt
local paint = { baseColor = { 0.4, 0.58, 0.07, 1 }, metallic = 0.8, roughness = 0.65, clearcoat = 1, clearcoatRoughness = 0.1 }
local none = R.dirtPaint(paint, R.dirtNew())
eq(none.baseColor[1], 0.4, 'no dirt, no change')
eq(none.clearcoat, 1, 'no dirt keeps the gloss')
local mud = R.dirtPaint(paint, { dust = 0, mud = 1, rubber = 0, grime = 0 })
eq(mud.clearcoat, 0, 'full mud takes the gloss')
eq(mud.baseColor[1] < 0.4 and mud.baseColor[1] > 0.3, true, 'mud keeps some of the paint colour')
local dust = R.dirtPaint(paint, { dust = 0.1, mud = 0, rubber = 0, grime = 0 })
eq(dust.clearcoat > 0.95, true, 'light dust keeps the gloss')
local dustFull = R.dirtPaint(paint, { dust = 1, mud = 0, rubber = 0, grime = 0 })
eq(dustFull.baseColor[1] > 0.4 and dustFull.baseColor[3] > 0.07, true, 'dust is light tan')
local rub = R.dirtPaint(paint, { dust = 0, mud = 0, rubber = 1, grime = 0 })
eq(rub.baseColor[1] < 0.4 and rub.baseColor[2] < 0.58, true, 'rubber is black')
eq(select(1, R.groundClass('MUD')), 'mud', 'mud ground')
eq(select(1, R.groundClass('DIRT_DUSTY')), 'loose', 'dirt is loose')
eq(select(1, R.groundClass('ASPHALT')), 'road', 'road')
eq(select(1, R.groundClass('METAL')), nil, 'unknown')
local d1 = R.dirtBuild(R.dirtNew(), 60, { loose = 1 }, 20, 0)
eq(d1.dust, 1, 'a minute of dry dirt road at speed: full dust')
eq(d1.mud, 0, 'no mud when it is dry')
local d2 = R.dirtBuild(R.dirtNew(), 60, { loose = 1 }, 20, 1)
eq(d2.dust, 0, 'wet loose ground gives no dust')
eq(d2.mud > 0.5, true, 'wet loose ground gives mud')
local d3 = R.dirtBuild(R.dirtNew(), 100000, { road = 1 }, 20, 0)
eq(d3.grime, R.CAP.grime, 'road film is capped')
eq(R.dirtBuild(R.dirtNew(), 10, { slip = 1 }, 20, 0).rubber, 0.4, 'a 10 s burnout')
local w = R.dirtWash({ dust = 1, mud = 1, rubber = 1, grime = 1 }, 30, 1, 0)
eq(w.dust, 0.5, 'rain washes dust fast')
eq(w.mud > 0.9, true, 'and mud slowly')
local w2 = R.dirtWash({ dust = 1, mud = 1, rubber = 1, grime = 1 }, 3, 0, 1)
eq(w2.dust, 0, 'water washes dust at once')
eq(w2.mud > 0.7, true, 'mud takes longer in water')
eq(R.dirtTotal(R.dirtClean({ dust = 1, mud = 1, rubber = 1, grime = 1 }, 1)), 0, 'a car wash cleans everything')

-- snow, bugs, frost
local function D(t) local d = R.dirtNew() for k, v in pairs(t) do d[k] = v end return d end
local sn = R.dirtBuild(R.dirtNew(), 90, { snowing = 1 }, 0, 0)
eq(sn.snow, 1, 'a standing car under full snow: a full coat in 90 s')
eq(R.dirtBuild(R.dirtNew(), 90, { snowing = 1 }, 20, 0).snow, 0, 'a fast car blows it off at once')
eq(R.dirtBuild(D({ snow = 1 }), 10, {}, 10, 0).snow, 0.5, 'blown off above 8 m/s: 2 m/s over for 10 s takes half')
eq(R.dirtBuild(D({ snow = 1 }), 900, { warm = true }, 0, 0).snow, 0, 'melts when warm')
eq(R.dirtBuild(D({ snow = 0.5 }), 900, {}, 0, 0).snow, 0.5, 'stays when cold and still')
eq(R.dirtBuild(R.dirtNew(), 300, {}, 38, 0).bugs, 0.5, 'bugs after 5 min at 38 m/s, capped at 0.5')
eq(R.dirtBuild(R.dirtNew(), 300, {}, 38, 1).bugs, 0, 'no bugs in the rain')
eq(R.dirtBuild(R.dirtNew(), 300, {}, 15, 0).bugs, 0, 'none when slow')
eq(R.dirtWash({ bugs = 1, snow = 1 }, 500, 1, 0).bugs, 0, 'rain washes bugs')
-- bug dynamics: warm air, dusk, rain, size, soaking
eq(R.bugRate(38, 22, nil, 0), 1 / 300, 'bugs in warm air at 38 m/s: 1/300 per second')
eq(R.bugRate(38, 4, nil, 0), 0, 'none in the cold')
assert(R.bugRate(38, 12, nil, 0) < R.bugRate(38, 22, nil, 0) and R.bugRate(38, 12, nil, 0) > 0, 'fewer in cool air')
assert(R.bugRate(38, 22, 0.245, 0) > 1.3 * R.bugRate(38, 22, 0.0, 0), 'more at dusk')
assert(R.bugRate(38, 22, 0.775, 0) > R.bugRate(38, 22, 0.5, 0), 'and at dawn, not at night')
eq(R.bugRate(38, 22, nil, 0.4), 0, 'none in the rain')
assert(R.bugRate(38, 45, nil, 0) < R.bugRate(38, 25, nil, 0), 'too hot for them')
assert(R.bugRate(38, nil, nil, 0) > 0, 'unknown air is mild')
assert(R.bugSize(0.5) > R.bugSize(0) and R.bugSize(0) == 1 and R.bugSize(5) == R.bugSize(1), 'splats grow with the amount, to a limit')
assert(R.dirtWash({ bugs = 1 }, 10, 1, 0, 0).bugs > R.dirtWash({ bugs = 1 }, 10, 1, 0, 90).bugs, 'rain soaks first, then washes: slow at the start')
eq(R.dirtWash({ bugs = 1 }, 10, 1, 0).bugs, R.dirtWash({ bugs = 1 }, 10, 1, 0, 90).bugs, 'without a soak time the old rate applies')
-- dust: the film climbs, the rain takes it from the top
eq(R.dustHeight(0), 0, 'no dust, no height') eq(R.dustHeight(1), 1, 'a full film reaches the roof')
assert(R.dustHeight(0.2) < R.dustHeight(0.5) and R.dustHeight(0.5) < R.dustHeight(0.9), 'more dust, higher')
eq(R.dustWashHeight(0), 1, 'dry: nothing washed') eq(R.dustWashHeight(60), 0, 'a minute of rain clears the film')
assert(R.dustWashHeight(20) < R.dustWashHeight(5), 'the wash comes down from the top')
assert(R.dirtBuild(R.dirtNew(), 60, { road = 1 }, 20, 0).dust > 0 and R.dirtBuild(R.dirtNew(), 60, { road = 1 }, 20, 0).dust < R.dirtBuild(R.dirtNew(), 60, { loose = 1 }, 20, 0).dust / 4, 'dry tarmac: a thin film, much slower than a dirt road')
eq(R.dirtBuild(R.dirtNew(), 60, { road = 1 }, 20, 1).dust, 0, 'none on wet tarmac')
eq(R.dirtWash({ snow = 1 }, 400, 1, 0).snow, 0, 'and snow')
eq(R.dirtWash({ dust = 0.5 }, 1, 0, 0).snow, 0, 'old saved states without the new kinds still work')
eq(R.dirtPaint({ baseColor = { 0, 0, 0, 1 } }, { snow = 1 }).baseColor[1] > 0.4, true, 'snow whitens the paint')
eq(R.snowing(0.5, 0), 1, 'precipitation below 1.5 C is snow')
eq(R.snowing(0.5, 10), 0, 'warm rain is not')
eq(R.snowing(0.5, nil), 0, 'unknown temperature: no snow')
local f = R.frostStep(0, 240, -6, -6, 0)
eq(f, 1, 'a cold night, cold engine: frost in minutes')
eq(R.frostStep(0, 240, 10, 10, 0), 0, 'none in the warm')
eq(R.frostStep(1, 100, -6, 85, 0) < 0.1, true, 'a warm engine clears it')
eq(R.frostStep(0.5, 10, -6, -6, 1) < 0.5, true, 'rain does not build frost')
eq(R.frostStep(0.5, 10, nil, nil, 0), 0.5, 'unknown temperature: unchanged')
-- spray
eq(R.spray({ dist = 10, lateral = 0.5, align = 1, speed = 25, len = 4.5 }) > 0.2, true, 'a car 10 m ahead at 25 m/s throws spray')
eq(R.spray({ dist = 30, lateral = 0, align = 1, speed = 25 }), 0, 'not beyond 25 m')
eq(R.spray({ dist = 10, lateral = 3.5, align = 1, speed = 25 }), 0, 'not in the next lane over')
eq(R.spray({ dist = 10, lateral = 0, align = -1, speed = 25 }), 0, 'not oncoming')
eq(R.spray({ dist = 10, lateral = 0, align = 1, speed = 3 }), 0, 'not when slow')
eq(R.spray({ dist = 10, lateral = 0, align = 1, speed = 25, len = 12 }) > R.spray({ dist = 10, lateral = 0, align = 1, speed = 25, len = 4.5 }), true, 'trucks throw more')
eq(R.spray({ dist = 5, lateral = 0, align = 1, speed = 25 }) > R.spray({ dist = 20, lateral = 0, align = 1, speed = 25 }), true, 'closer is more')
eq(R.sprayWet(0), 0, 'a dry road: no spray')
eq(R.sprayWet(1), 1, 'a wet road: full')
-- splash
local sl, sr, sh = R.splash(20, 1, 0, 0.5)
eq(sl > 1 and sr == 0 and sh == 0, true, 'one side in a puddle: that side only, no sheet')
local _, _, sh2 = R.splash(25, 1, 1, 1)
eq(sh2 > 0.8, true, 'both sides, deep, fast: a sheet over the windscreen')
local a1, b1, c1 = R.splash(8, 1, 1, 1)
eq(a1 + b1 + c1, 0, 'slow: nothing')
eq(R.splash(20, 0, 0, 1), 0, 'no wheel in water: nothing')
-- settings migration
do
  local on, speed, moved = R.migrate({ mud = { buildup = false } }, 0)
  eq(on and speed == 1 and moved, true, 'an old build-up off is turned on once, and the Options value 0 becomes 1')
  local on2, speed2, moved2 = R.migrate({ settingsVersion = 2, mud = { buildup = false } }, 0)
  eq(on2 or speed2 or moved2, false, 'a deliberate off after the migration stays off')
  local on3, speed3, moved3 = R.migrate({ mud = { buildup = true } }, 1.5)
  eq(on3 == false and speed3 == nil and moved3, true, 'an on stays as it is, the version moves up')
end
print('carSurfaceFx rules: ' .. n .. ' checks passed')
