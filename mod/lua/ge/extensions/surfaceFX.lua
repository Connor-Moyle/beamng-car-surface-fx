-- Car Surface FX: the old modder API (Surface FX / Enhanced Skid Marks, MODDER_API.md) kept working, so a mod that calls surfaceFX.registerModule{...} still gets its settings
-- page. The page now appears in the Mods menu (Wrench Works) as its own entry instead of an app tab: the old controls are turned into the Mods-menu fields (bool, range -> slider/int,
-- colour -> color, texturePicker -> texture, dropdown -> enum, button, group -> one heading per item). Without the Mods menu the module still runs and gets its callbacks, but has no page.
local M = { csfxShim = true }
local logTag = 'surfaceFX'
local modules, order = {}, {}
local warned = {}

local CONTROL_TYPES = { bool = true, range = true, colour = true, texturePicker = true, dropdown = true, button = true, group = true }

local function warnOnce(what) if not warned[what] then warned[what] = true log('W', logTag, what) end end

local function validCtrl(c)
  if type(c) ~= 'table' then return false, 'a control is not a table' end
  if type(c.key) ~= 'string' or c.key == '' then return false, 'a control is missing a string "key"' end
  if not CONTROL_TYPES[c.type] then return false, ('control "%s" has unknown type "%s"'):format(c.key, tostring(c.type)) end
  return true
end
M.validCtrl = validCtrl

local function resolveFn(v) if type(v) == 'function' then local o, l = pcall(v) return (o and l) or {} end return v end

local function schemaDefaults(schema)
  local out = {}
  for _, c in ipairs(schema) do if c.default ~= nil then out[c.key] = c.default end end
  return out
end
local function withDefaults(schema, stored)
  local out = schemaDefaults(schema)
  if type(stored) == 'table' then for k, v in pairs(stored) do out[k] = v end end
  return out
end
M.withDefaults = withDefaults

-- ---- the value of one control: managed (surfaceFXStore + onSettingsChanged) or full control (getValues + onSet)
local function read(d, key, item)
  if type(d.getValues) == 'function' then
    local o, v = pcall(d.getValues)
    v = (o and type(v) == 'table') and v or {}
    if item then local g = v[item.group] return g and g[item.name] and g[item.name][key] end
    return v[key]
  end
  local all = withDefaults(d.settingsSchema, surfaceFXStore and surfaceFXStore.getAll(d.id))
  return all[key]
end
local function write(d, key, value, item)
  pcall(function()
    if type(d.onSet) == 'function' then
      if item then d.onSet(key, value, item.name) else d.onSet(key, value) end
    elseif type(d.onSettingsChanged) == 'function' then
      if surfaceFXStore then surfaceFXStore.set(d.id, key, value) end
      d.onSettingsChanged(withDefaults(d.settingsSchema, surfaceFXStore and surfaceFXStore.getAll(d.id) or { [key] = value }))
    end
  end)
end

-- ---- one old control -> one Mods-menu field
local function field(d, c, id, group, item)
  local f = { id = id, tab = 'main', group = group, label = c.label or c.key, tooltip = c.tip or c.tooltip or c.label or c.key, default = c.default, apply = 'live' }
  local key = c.key
  f.store = { kind = 'custom',
    get = function() local v = read(d, key, item) if v == nil then v = c.default end return v end,
    set = function(v) write(d, key, v, item) end }
  if c.type == 'bool' then f.type = 'bool'
  elseif c.type == 'range' then
    f.type = c.int and 'int' or 'slider'
    f.min, f.max, f.step = c.min or 0, c.max or 1, c.step
    if f.default == nil then f.default = f.min end
  elseif c.type == 'colour' then
    f.type = 'color'
    local dv = c.default
    f.default = type(dv) == 'table' and { r = dv.r or dv[1] or 1, g = dv.g or dv[2] or 1, b = dv.b or dv[3] or 1 } or { r = 1, g = 1, b = 1 }
    f.store = { kind = 'custom',
      get = function() local v = read(d, key, item) if type(v) ~= 'table' then return f.default end return { r = v.r or v[1] or 0, g = v.g or v[2] or 0, b = v.b or v[3] or 0 } end,
      set = function(v) write(d, key, { v.r, v.g, v.b }, item) end }
  elseif c.type == 'dropdown' then
    f.type = 'enum'
    f.options = {}
    for _, o in ipairs(resolveFn(c.options) or {}) do f.options[#f.options + 1] = { id = tostring(o), label = tostring(o) } end
    if f.default == nil and f.options[1] then f.default = f.options[1].id end
  elseif c.type == 'texturePicker' then
    local folder = c.folder or (item and resolveFn(c.folderByItem) and resolveFn(c.folderByItem)[item.name]) or ''
    folder = '/' .. tostring(folder):gsub('^/+', ''):gsub('/*$', '/')
    f.type, f.folder, f.exts, f.thumbs, f.none = 'texture', folder, { 'png', 'jpg', 'dds' }, true, true
    f.default = f.default and (folder .. f.default) or ''
    f.store = { kind = 'custom',
      get = function() local v = read(d, key, item) if v == nil or v == '' then return f.default end return folder .. tostring(v):match('([^/\\]+)$') end,
      set = function(v) write(d, key, tostring(v):match('([^/\\]+)$') or '', item) end }
  else                                                                     -- button
    f.type, f.store, f.default = 'button', nil, nil
    f.action = function() pcall(function() if d.onAction then if item then d.onAction(key, item.name) else d.onAction(key) end end end) return 'done' end
  end
  return f
end

local function onItem(sc, name)                                              -- a sub-control may be limited to some items (onlyItems)
  if type(sc.onlyItems) ~= 'table' then return true end
  for _, n in ipairs(sc.onlyItems) do if n == name then return true end end
  return false
end

-- the whole schema of a module as a Mods-menu entry
function M.schemaOf(d)
  local fields = {}
  for i, c in ipairs(d.settingsSchema) do
    if c.type == 'group' then
      for _, name in ipairs(resolveFn(c.items) or {}) do
        fields[#fields + 1] = { id = 'h' .. i .. '_' .. name, tab = 'main', type = 'heading', label = tostring(name) }
        for j, sc in ipairs(c.schema or {}) do
          if validCtrl(sc) and sc.type ~= 'group' and onItem(sc, name) then
            fields[#fields + 1] = field(d, sc, 'g' .. i .. '_' .. name .. '_' .. j, tostring(name), { group = c.key, name = name })
          end
        end
      end
    else
      fields[#fields + 1] = field(d, c, 'c' .. i, nil, nil)
    end
  end
  local mod = 'csfx_ext_' .. d.id:lower():gsub('[^a-z0-9]', '_')
  return { mod = mod, title = d.name, icon = 'wrench', order = 90, tabs = { { id = 'main', title = d.name } }, fields = fields }
end

local function publish(d)
  local S = rawget(_G, 'slrr_settings')
  if S and S.register then local ok, err = pcall(function() S.register(M.schemaOf(d)) end) if not ok then log('E', logTag, 'page of "' .. d.id .. '": ' .. tostring(err)) end end
end

function M.registerModule(def)
  if type(def) ~= 'table' then log('E', logTag, 'registerModule: def is not a table') return false end
  if type(def.id) ~= 'string' or def.id == '' then log('E', logTag, 'registerModule: missing string "id"') return false end
  if type(def.name) ~= 'string' then def.name = def.id end
  if type(def.settingsSchema) ~= 'table' then log('E', logTag, ('registerModule "%s": "settingsSchema" must be a table'):format(def.id)) return false end
  local ok = true
  for _, c in ipairs(def.settingsSchema) do
    local cok, reason = validCtrl(c)
    if not cok then log('E', logTag, ('registerModule "%s": %s'):format(def.id, reason)) ok = false end
  end
  if not ok then return false end
  if not modules[def.id] then order[#order + 1] = def.id end
  modules[def.id] = def
  log('I', logTag, ('registered module "%s" (%d controls)'):format(def.id, #def.settingsSchema))
  publish(def)
  if not rawget(_G, 'slrr_settings') then warnOnce('no Mods menu (Wrench Works) is loaded: module pages are not shown, callbacks still run') end
  return true
end
M.register = M.registerModule                                              -- the short name some mods use

function M.onSlrrSettingsReady() for _, id in ipairs(order) do publish(modules[id]) end end

-- the old app calls, kept for a mod that drives them directly
function M.uiSet(id, key, value) local d = modules[id] if d then write(d, key, value) end end
function M.uiAction(id, key) local d = modules[id] if d then pcall(function() if d.onAction then d.onAction(key) end end) end end
function M.uiSetGroup(id, groupKey, item, subKey, value) local d = modules[id] if d then write(d, subKey, value, { group = groupKey, name = item }) end end
function M.uiActionGroup(id, groupKey, item, subKey) local d = modules[id] if d then pcall(function() if d.onAction then d.onAction(subKey, item) end end) end end
function M.uiGetModules()
  local out = {}
  for _, id in ipairs(order) do
    local d = modules[id]
    local schema = {}
    for i, c in ipairs(d.settingsSchema) do
      local r = {}
      for k, v in pairs(c) do r[k] = v end
      r.items, r.options = resolveFn(r.items), resolveFn(r.options)
      schema[i] = r
    end
    local values = type(d.getValues) == 'function' and (select(2, pcall(d.getValues))) or withDefaults(d.settingsSchema, surfaceFXStore and surfaceFXStore.getAll(id))
    out[#out + 1] = { id = id, name = d.name, values = type(values) == 'table' and values or {}, schema = schema }
  end
  return out
end

function M.tickModules(dt) for _, id in ipairs(order) do local d = modules[id] if d and d.onUpdate then pcall(d.onUpdate, dt) end end end
function M.vehSpawned(veh) for _, id in ipairs(order) do local d = modules[id] if d and d.onVehicleSpawned then pcall(d.onVehicleSpawned, veh) end end end
function M.getModuleCount() return #order end
function M.onUpdate(dt) M.tickModules(dt) end
function M.onVehicleSpawned(id, veh)
  veh = veh or (be and be:getObjectByID(id))
  if veh then M.vehSpawned(veh) end
end

return M
