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
eq(R.glassMode('vivace_glass'), 'color', 'outside glass uses its colour map')
R.outsideMode = 'emissive'
eq(R.glassMode('vivace_glass'), 'emissive', 'the outside mode can be switched')
R.outsideMode = 'color'
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
print('carSurfaceFx rules: ' .. n .. ' checks passed')
