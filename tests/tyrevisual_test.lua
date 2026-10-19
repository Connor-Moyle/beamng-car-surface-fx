-- carSurfaceFx/tyrevisual.lua against mocked materials: the tyre materials are found, a worn stage is laid on and put back as it was.
local fields = { tire_01a = { detailNormalMap = '', detailNormalMapStrength = '', detailScale = '' }, covet_main = { detailNormalMap = 'x' } }
local reloads = 0
scenetree = { findObject = function(n) local f = fields[n] if not f then return nil end
  return { getField = function(_, k) return f[k] end, setField = function(_, k, _, v) f[k] = v end, reload = function() reloads = reloads + 1 end } end }
-- the mock's setField takes (name, layer, value)
scenetree.findObject = function(n) local f = fields[n] if not f then return nil end
  return { getField = function(_, k) return f[k] end, setField = function(_, k, layer, v) f[k] = v end, reload = function() reloads = reloads + 1 end } end
be = { getPlayerVehicle = function() return { getMaterialNames = function() return { 'tire_01a', 'covet_main', 'tire_shadow', 'ibishu_rim_01' } end } end }
local T = dofile('mod/lua/ge/extensions/carSurfaceFx/tyrevisual.lua')
assert(T.list() == 'tire_01a', 'only the tyre material: ' .. T.list())
assert(T.set(0.1):find('restored', 1, true), 'a new tyre is left alone')
assert(T.set(0.5):find('1 tyre materials', 1, true) and fields.tire_01a.detailNormalMap:find('tyre_worn', 1, true), 'worn rubber at half')
assert(tonumber(fields.tire_01a.detailNormalMapStrength) > 0.3, 'its strength grows with the wear')
assert(T.set(0.9):find('tyre_belts', 1, true) and fields.tire_01a.detailNormalMap:find('tyre_belts', 1, true), 'the belts at the end')
assert(T.set(0.9, true):find('tyre_damage', 1, true), 'the damage map on request')
assert(T.clear():find('restored 1', 1, true) and fields.tire_01a.detailNormalMap == '' and fields.tire_01a.detailScale == '' and fields.covet_main.detailNormalMap == 'x', 'put back as it was, nothing else touched')
print('carSurfaceFx tyrevisual: ok')
