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

eq(R.isPaintStage({ clearCoatFactor = 1 }), true, 'clear coat is paint')
eq(R.isPaintStage({ colorPaletteMap = '/a.png' }), true, 'palette is paint')
eq(R.isPaintStage({ roughnessFactor = 0.5 }), false, 'plain stage')
eq(R.isPaintMaterial({ Stages = { {}, { clearCoatFactor = 1 } } }), true, 'material with a paint stage')
eq(R.isPaintMaterial({ Stages = { { clearCoatFactor = 1 } }, translucent = true }), false, 'glass is not paint')

local w = R.wetFields({ baseColorFactor = { 1, 0.5, 0, 1 }, roughnessFactor = 0.8 }, 3)
eq(w.baseColorFactor, '0.7500 0.3750 0.0000 1.0000', 'darker')
eq(w.roughnessFactor, '0.4000', 'glossier')
eq(w.normalDetailMap, R.DROPLETS, 'droplets filled in')
eq(w.detailScale, '6 6', 'detail scale set when unset')
local keep = R.wetFields({ normalDetailMap = '/x.png', detailScale = { 2, 2 } }, 1)
eq(keep.normalDetailMap, nil, 'own detail map kept')
eq(keep.detailScale, nil, 'own detail scale kept')

eq(R.fieldString({ 1, 0.5 }), '1 0.5', 'array')
eq(R.fieldString(true), '1', 'bool')
print('carSurfaceFx rules: ' .. n .. ' checks passed')
