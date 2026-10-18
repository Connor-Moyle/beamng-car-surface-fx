-- P15: the old modder API (surfaceFX.registerModule, surfaceFXStore, surfaceFXBody.wash) forwarding to the Mods menu and the new modules.
local saved = { log = log, slrr_settings = rawget(_G, 'slrr_settings'), jsonReadFile = jsonReadFile, jsonWriteFile = jsonWriteFile, surfaceFXStore = rawget(_G, 'surfaceFXStore'), carSurfaceFx = rawget(_G, 'carSurfaceFx'), be = be }
local logs = {}
log = function(l, t, text) logs[#logs + 1] = l .. ' ' .. tostring(text) end
local file = {}
jsonReadFile = function() return file.data end
jsonWriteFile = function(_, t) file.data = t end
local registered
slrr_settings = { register = function(s) registered = s end }
surfaceFXStore = dofile('mod/lua/ge/extensions/surfaceFXStore.lua')
local W = dofile('mod/lua/ge/extensions/surfaceFX.lua')

assert(not W.registerModule({}) and not W.registerModule({ id = 'x', settingsSchema = { { key = 'a', type = 'nope' } } }) and not W.registerModule({ id = 'x', settingsSchema = 3 }), 'bad modules are rejected, not thrown')
assert(W.getModuleCount() == 0)

local applied, pressed = nil, nil
local ok = W.registerModule({ id = 'myFx', name = 'My FX', settingsSchema = {
  { key = 'enabled', type = 'bool', label = 'On', default = true },
  { key = 'amount', type = 'range', label = 'Amount', min = 0, max = 2, step = 0.1, default = 0.5 },
  { key = 'n', type = 'range', int = true, min = 1, max = 5, default = 2 },
  { key = 'tint', type = 'colour', label = 'Tint', default = { 1, 0, 0 } },
  { key = 'style', type = 'dropdown', label = 'Style', options = function() return { 'soft', 'hard' } end, default = 'hard' },
  { key = 'tex', type = 'texturePicker', label = 'Texture', folder = 'myMod/art/', default = 'a.png' },
  { key = 'go', type = 'button', label = 'Go' },
  { key = 'per', type = 'group', label = 'Per', items = function() return { 'dirt', 'sand' } end, schema = { { key = 'op', type = 'range', min = 0, max = 1, default = 0.3 }, { key = 'only', type = 'bool', onlyItems = { 'sand' } } } },
}, onSettingsChanged = function(v) applied = v end, onAction = function(k) pressed = k end })
assert(ok and W.getModuleCount() == 1 and registered, 'registered and the page is made')
assert(registered.mod == 'csfx_ext_myfx' and #registered.tabs == 1, 'its own Mods-menu entry: ' .. tostring(registered.mod))
local by = {}
for _, f in ipairs(registered.fields) do by[f.id] = f end
assert(by.c1.type == 'bool' and by.c2.type == 'slider' and by.c3.type == 'int' and by.c4.type == 'color' and by.c5.type == 'enum' and by.c6.type == 'texture' and by.c7.type == 'button', 'control types map')
assert(by.c5.options[2].id == 'hard' and by.c5.default == 'hard' and by.c6.folder == '/myMod/art/' and by.c6.default == '/myMod/art/a.png', 'dropdown options (a live function) and the texture folder')
assert(by.h8_dirt.type == 'heading' and by.g8_dirt_1.group == 'dirt' and by.g8_sand_2 and not by.g8_dirt_2, 'a group is one heading per item, onlyItems respected')
-- values: defaults first, then managed storage
assert(by.c1.store.get() == true and by.c2.store.get() == 0.5 and by.c4.store.get().r == 1)
by.c2.store.set(1.5)
assert(applied and applied.amount == 1.5 and applied.enabled == true and applied.style == 'hard', 'the whole set with defaults is handed back')
assert(by.c2.store.get() == 1.5 and surfaceFXStore.get('myFx', 'amount') == 1.5, 'and stored')
by.c4.store.set({ r = 0, g = 1, b = 0 })
assert(applied.tint[2] == 1 and by.c4.store.get().g == 1, 'a colour is stored as {r,g,b} like before')
by.c6.store.set('/myMod/art/b.png')
assert(applied.tex == 'b.png' and by.c6.store.get() == '/myMod/art/b.png', 'a texture is stored as a file name like before')
by.c7.action()
assert(pressed == 'go', 'a button fires onAction(key)')

-- full control: getValues / onSet with the item
local sets = {}
W.registerModule({ id = 'full', settingsSchema = { { key = 'a', type = 'bool' }, { key = 'g', type = 'group', items = { 'x' }, schema = { { key = 'op', type = 'range' } } } },
  getValues = function() return { a = true, g = { x = { op = 0.7 } } } end, onSet = function(k, v, item) sets[#sets + 1] = { k, v, item } end })
local fb = {}
for _, f in ipairs(registered.fields) do fb[f.id] = f end
assert(fb.c1.store.get() == true and fb.g2_x_1.store.get() == 0.7, 'getValues feeds the page, group values by item')
fb.g2_x_1.store.set(0.2)
assert(sets[1][1] == 'op' and sets[1][2] == 0.2 and sets[1][3] == 'x', 'onSet(key, value, item)')

-- callbacks
local ticks, spawned = 0, nil
W.registerModule({ id = 'tick', settingsSchema = {}, onUpdate = function() ticks = ticks + 1 end, onVehicleSpawned = function(v) spawned = v end })
W.onUpdate(0.1) W.onVehicleSpawned(1, 'veh')
assert(ticks == 1 and spawned == 'veh', 'onUpdate and onVehicleSpawned fan out')
-- the page is made again when the registry is ready
registered = nil
W.onSlrrSettingsReady()
assert(registered, 'registered again when the Mods menu is ready')
assert(W.csfxShim and surfaceFXStore.csfxShim, 'marked, so the old-mod detector leaves them alone')

-- the store keeps its file format
assert(file.data.myFx.amount == 1.5, 'same file layout as the old mod')

-- surfaceFXBody
local washed = 0
carSurfaceFx = { wash = function() washed = washed + 1 return 'ok' end }
local B = dofile('mod/lua/ge/extensions/surfaceFXBody.lua')
assert(B.wash() == 'ok' and washed == 1 and B.dump() == nil, 'wash forwards, dump is a stub')

log, slrr_settings, jsonReadFile, jsonWriteFile, surfaceFXStore, carSurfaceFx, be = saved.log, saved.slrr_settings, saved.jsonReadFile, saved.jsonWriteFile, saved.surfaceFXStore, saved.carSurfaceFx, saved.be
print('carSurfaceFx shim: ok')
