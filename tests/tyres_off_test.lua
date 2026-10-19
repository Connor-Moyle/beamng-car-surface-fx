-- The tyre simulation ships OFF everywhere (the reviewer's condition for having it in master): the rules' defaults, the Mods page, the presets of the page, and the Quick setup levels of the main Mods page.
local R = require('csfx_tyrerules')
assert(R.defaults().enabled == false, 'the tyre rules default to off')
local Schema = require('carSurfaceFx/tyresSchema')
local reg = Schema.build({}, { rules = R, read = function() return {} end, write = function() end, reload = function() end })
local on
for _, f in ipairs(reg.fields) do
  if f.store and f.store.kind == 'json' and f.store.path == 'enabled' then on = f end
  assert(not f.presets, f.id .. ': no Quick setup level touches a tyre field')
end
assert(on and on.default == false, 'the Tyres switch shows off by default')
local pre = nil
for _, f in ipairs(reg.fields) do if f.id == 'ty_preset' then pre = f end end
assert(pre.default == 'off' and pre.store.get() == 'off', 'the page preset starts at Off')
print('carSurfaceFx tyres off by default: ok')
