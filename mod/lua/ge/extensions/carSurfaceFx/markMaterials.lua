-- Car Surface FX: the materials of the ground marks (art/surfacefx/marks/main.materials.json, made by tools/make_mark_textures.py). The game may or may not scan a mod's
-- art folder for material files, so this makes sure each one exists: a name that is not in the scene tree is built from the file's entry with createObject('Material') and
-- the same fields, as the game would have loaded it.
local M = {}

M.FILE = '/art/surfacefx/marks/main.materials.json'
M.INDEX = '/art/surfacefx/marks/marks_index.json'

local cache = {}                                  -- material file -> its entries

function M.entries(file)
  file = file or M.FILE
  if cache[file] then return cache[file] end
  local ok, data = pcall(function() return jsonReadFile and jsonReadFile(file) end)
  cache[file] = ok and type(data) == 'table' and data or {}
  return cache[file]
end

function M.index()
  local ok, data = pcall(function() return jsonReadFile and jsonReadFile(M.INDEX) end)
  return ok and type(data) == 'table' and data.types or {}
end

local function text(v)
  if type(v) == 'boolean' then return v and '1' or '0' end
  if type(v) == 'table' then
    local out = {}
    for i, x in ipairs(v) do out[i] = tostring(x) end
    return table.concat(out, ' ')
  end
  return tostring(v)
end

-- the material `name` exists afterwards (made from the file when the game did not load it); false and why when it cannot be
function M.ensure(name, file)
  file = file or M.FILE
  if scenetree and scenetree.findObject(name) then return true end
  local e = M.entries(file)[name]
  if not e then return false, 'no entry for ' .. tostring(name) .. ' in ' .. file end
  local ok, err = pcall(function()
    local m = createObject('Material')
    m:setField('mapTo', 0, name)
    m:setField('version', 0, tostring(e.version or 1.5))
    m:setField('translucent', 0, text(e.translucent))
    m:setField('translucentZWrite', 0, text(e.translucentZWrite))
    if e.materialTag0 then m:setField('materialTag0', 0, e.materialTag0) end
    for layer, stage in ipairs(e.Stages or {}) do
      for k, v in pairs(stage) do m:setField(k, layer - 1, text(v)) end
    end
    m:registerObject(name)
    if Sim and Sim.upcast then Sim.upcast(m):reload() end
  end)
  if not ok then return false, tostring(err) end
  return true
end

-- every material of the file
function M.ensureAll()
  local made, failed = 0, {}
  for name in pairs(M.entries()) do
    local ok, why = M.ensure(name)
    if ok then made = made + 1 else failed[#failed + 1] = name .. ': ' .. tostring(why) end
  end
  return made, failed
end

function M.reset() cache = {} end

return M
