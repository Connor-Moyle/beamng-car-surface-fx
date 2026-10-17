-- Tests of mod/lua/ge/extensions/carSurfaceFx/rules.lua (run by tools/luatest.js).
local R = require('carSurfaceFx/rules')
local n = 0
local function eq(a, b, what) n = n + 1 if a ~= b then error(what .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end end

eq(R.level(0, 0), 0, 'dry')
eq(R.level(0.1, 0), 1, 'damp')
eq(R.level(0.5, 0), 2, 'wet')
eq(R.level(0.9, 0), 3, 'soaked')
eq(R.level(0.38, 2), 2, 'hysteresis holds rung 2 just under its threshold')
eq(R.level(0.30, 2), 1, 'falls to rung 1')
eq(R.level(0.05, 1), 1, 'hysteresis holds rung 1')
eq(R.level(0.0, 3), 0, 'dries to 0')

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

local w = R.wetFields({ baseColorFactor = '1 0.5 0 1', roughnessFactor = '0.8' }, 3)
eq(w.baseColorFactor, '0.7500 0.3750 0.0000 1.0000', 'darker')
eq(w.roughnessFactor, '0.4000', 'glossier')
eq(w.detailNormalMap, R.DROPLETS, 'droplets filled in')
eq(w.detailScale, '6 6', 'detail scale set')
local keep = R.wetFields({ detailMap = '/x.png' }, 1)
eq(keep.detailNormalMap, nil, 'a stage with another detail map is left alone')
local peel = R.wetFields({ detailNormalMap = '/orange_peel.png', detailScale = '128 64' }, 1)
eq(peel.detailNormalMap, R.DROPLETS, 'beads replace the orange peel while wet')

local dp = R.dirtPaint({ baseColor = { 0.4, 0.58, 0.07, 1 }, metallic = 0.8, roughness = 0.65, clearcoat = 1, clearcoatRoughness = 0.1 }, 1)
eq(dp.clearcoat, 0, 'dirt kills the clear coat')
eq(dp.baseColor[1], 0.30, 'full dirt is the dirt colour')
eq(math.abs(dp.metallic - 0.16) < 1e-9, true, 'dirt dulls the metal')
eq(R.dirtPaint({ baseColor = { 1, 0, 0, 1 }, roughness = 0.5 }, 0).baseColor[1], 1, 'no dirt, no change')
print('carSurfaceFx rules: ' .. n .. ' checks passed')
