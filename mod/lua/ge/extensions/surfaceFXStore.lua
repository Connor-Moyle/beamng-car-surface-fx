-- Car Surface FX: the old managed storage for other mods' modules (MODDER_API.md), same file and same calls as before, so saved values survive the move.
local M = { csfxShim = true }
local FILE = 'settings/fatkiwi_surfaceFX_modules.json'
local data, loaded = {}, false

local function load()
  if loaded then return end
  loaded = true
  local ok, d = pcall(jsonReadFile, FILE)
  if ok and type(d) == 'table' then data = d end
end

function M.set(id, key, value)
  load()
  data[id] = data[id] or {}
  data[id][key] = value
  pcall(jsonWriteFile, FILE, data, true)
end
function M.get(id, key, default)
  load()
  local m = data[id]
  if m and m[key] ~= nil then return m[key] end
  return default
end
function M.getAll(id) load() return data[id] or {} end

return M
