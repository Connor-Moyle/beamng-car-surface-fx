-- The Mods page "Tyres" (carSurfaceFx/tyresSchema.lua): every cfg value of the tyre rules is a field, defaults sit inside their ranges, the presets write what they say. No game calls.
local R = require('csfx_tyrerules')
local Schema = require('carSurfaceFx/tyresSchema')

local store, reloads = {}, 0
local reg = Schema.build({}, { rules = R, read = function() return store end, write = function(t) store = t end, reload = function() reloads = reloads + 1 end })
assert(reg.mod and reg.title == 'Tyres' and #reg.tabs == 7, 'seven tabs')
local TYPES = { bool = 1, slider = 1, int = 1, enum = 1, note = 1 }
local tabs, ids, byPath = {}, {}, {}
for _, t in ipairs(reg.tabs) do tabs[t.id] = true assert(t.title and t.description, 'tab ' .. t.id .. ' has a title and a description') end
for _, f in ipairs(reg.fields) do
  assert(f.id and not ids[f.id], 'unique field id ' .. tostring(f.id)) ids[f.id] = f
  assert(tabs[f.tab], f.id .. ': tab exists')
  assert(TYPES[f.type], f.id .. ': known type ' .. tostring(f.type))
  assert(f.label and #f.label > 2 and f.tooltip and #f.tooltip > 10, f.id .. ': label and tooltip')
  assert(f.group, f.id .. ': in a group')
  if f.type ~= 'note' then
    assert(f.default ~= nil and f.store, f.id .. ': default and store')
    if f.type == 'slider' or f.type == 'int' then
      assert(type(f.default) == 'number' and f.default >= f.min and f.default <= f.max, f.id .. ': default ' .. tostring(f.default) .. ' within ' .. f.min .. '..' .. f.max)
    end
    if f.store.kind == 'json' then byPath[f.store.path] = f end
    if f.type == 'bool' then assert(f.feature == true, f.id .. ': an on/off switch is tagged as a feature') end
  end
end

-- every value of the rules' cfg has a field (the debris shares are one slider; the rubber density is a constant)
local NOT_SETTINGS = { ['debris.density'] = true, ['debris.minFrac'] = true, ['debris.maxFrac'] = true,
  ['marbles.burnLoss'] = true, ['marbles.mergeR'] = true, ['marbles.minG'] = true }      -- (the marbles' fixed constants: the share of a patch a fire uses up, the merge radius, the grams below which a patch is gone)
local missing = {}
local function walk(t, prefix)
  for k, v in pairs(t) do
    local path = prefix == '' and k or (prefix .. '.' .. k)
    if type(v) == 'table' then walk(v, path) elseif not NOT_SETTINGS[path] and not byPath[path] then missing[#missing + 1] = path end
  end
end
walk(R.defaults(), '')
table.sort(missing)
assert(#missing == 0, 'every cfg value has a field; without: ' .. table.concat(missing, ', '))
assert(ids.ty_debris_amount, 'the debris share is one slider')

-- every compound value of the table is a field of its compound
local compoundFields = 0
for name, c in pairs(R.COMPOUNDS) do
  for k in pairs(c) do
    local f = byPath['compounds.' .. name .. '.' .. k]
    assert(f and f.default == c[k] and f.visibleIf and f.visibleIf.equals == name and f.advanced, 'compound field ' .. name .. '.' .. k)
    compoundFields = compoundFields + 1
  end
end
assert(compoundFields > 150, 'the compounds are all there: ' .. compoundFields)

-- the cautions: blowout damage is off, and its force cap cannot be raised above 3000
assert(byPath['enabled'].default == false, 'the tyre simulation is off until it is switched on, as the game side treats a missing file')
assert(byPath['blowout.enabled'].default == false, 'blowout damage is off by default')
assert(byPath['blowout.maxForce'].max == 3000 and byPath['blowout.maxForce'].default <= 3000, 'the blowout force cap stays at 3000')
assert(byPath['fires'].label == 'Tyre fires' and byPath['fireSpread'].label == 'Fires can spread to the car', 'the fire labels')
assert(byPath['enabled'] and not byPath['enabled'].advanced and byPath['wearRate'] and not byPath['wearRate'].advanced and byPath['surface.ice'].advanced, 'common values normal, the rest advanced')

-- the presets
local preset = ids.ty_preset
assert(preset.store.get() == 'off' and R.defaults().enabled == false, 'the start is Off: the tyre simulation ships off')
preset.store.set('arcade')
assert(store.enabled == true and store.wearRate == 0.3 and store.heatRate == 0.6 and store.coldGrip == 0.3 and store.hotGrip == 0.3 and store.flat.enabled == false and store.fires == false and store.blowout.enabled == false, 'Arcade')
assert(store.deadZone == R.defaults().deadZone and store.flat.minDepth == R.defaults().flat.minDepth and store.preset == 'arcade' and preset.store.get() == 'arcade', 'Arcade keeps the other values at their defaults')
preset.store.set('off')
assert(store.enabled == false and store.wearRate == 1.0 and preset.store.get() == 'off', 'Off')
preset.store.set('realistic')
assert(store.enabled == true and store.fires == true and store.blowout.enabled == false and store.wearRate == 1.0, 'Realistic is the defaults with the simulation on')
assert(reloads == 3, 'a preset reloads the settings')
preset.store.set('nonsense')
assert(preset.store.get() == 'realistic' and reloads == 3, 'an unknown preset is ignored')
assert(ids.ty_preset.default == 'off' and byPath['enabled'].default == false, 'the page shows the simulation off by default')

-- the debris amount scales both shares
local amount = ids.ty_debris_amount
assert(amount.store.get() == 1, 'debris amount 1 at the defaults')
amount.store.set(0.5)
assert(math.abs(store.debris.minFrac - 0.15) < 1e-9 and math.abs(store.debris.maxFrac - 0.4) < 1e-9 and amount.store.get() == 0.5, 'half the debris')
amount.store.set(1.25)
assert(store.debris.maxFrac == 1 and store.debris.minFrac <= 1, 'the share never goes over 1')
print('tyres schema: ok, ' .. #reg.fields .. ' fields')
