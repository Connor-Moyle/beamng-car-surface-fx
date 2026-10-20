-- Car Surface FX: which ground a map's own materials count as (port P12). A wheel only ever reports a collision-type id; the cars know the game's own ids by the names in particles.json.
-- A map with ground models of its own (a new collision type) says what they are in a json file, and the rest are guessed by name:
--   /carSurfaceFx/<anything>.json   or the old Surface FX folder   /dirtSkidMarks/<anything>.json     (every json in either folder is read when the level loads)
--   { "mapName": "my_level" (a part of the level path; "" or "*" or "all" = every map),
--     "materials": { "dirt": ["dust", "dryearth"], "sand": ["redsand", "beach"], "mud": ["bog"], "gravel": ["scree"], "grass": ["meadow"], "snow": [...], "ice": [...], "tarmac": [...] } }
-- A name is a ground model of the level (the map maker's own) or a game material name. An explicit entry wins over the guess. The result is the id -> kind table the cars get
-- (carSurfaceFxMarks.setMaterials). The rules (guess, file merge, id resolution) are pure and tested by tests/surfaces_test.lua.
local M = {}

M.KINDS = { 'dirt', 'sand', 'gravel', 'mud', 'grass', 'ice', 'snow', 'tarmac' }
local KIND = {}
for _, k in ipairs(M.KINDS) do KIND[k] = true end
M.FOLDERS = { '/carSurfaceFx/', '/dirtSkidMarks/' }

-- the guess by name, first match wins (words found in the name, lower case). Order matters: 'snow' before 'ice' before the soils, 'mud' before 'dirt'.
M.GUESS = {
  { 'snow', 'snow' }, { 'ice', 'ice' }, { 'frozen', 'ice' }, { 'mud', 'mud' }, { 'bog', 'mud' }, { 'swamp', 'mud' }, { 'clay', 'mud' },
  { 'sand', 'sand' }, { 'beach', 'sand' }, { 'dune', 'sand' }, { 'desert', 'sand' },
  { 'gravel', 'gravel' }, { 'scree', 'gravel' }, { 'pebble', 'gravel' }, { 'rubble', 'gravel' }, { 'crushed', 'gravel' }, { 'ballast', 'gravel' },
  { 'grass', 'grass' }, { 'meadow', 'grass' }, { 'lawn', 'grass' }, { 'turf', 'grass' }, { 'field', 'grass' }, { 'moss', 'grass' },
  { 'dirt', 'dirt' }, { 'dust', 'dirt' }, { 'soil', 'dirt' }, { 'earth', 'dirt' }, { 'trail', 'dirt' }, { 'track', 'dirt' }, { 'dry', 'dirt' }, { 'ground', 'dirt' },
}

function M.guess(name)
  local n = tostring(name or ''):lower()
  for _, g in ipairs(M.GUESS) do if n:find(g[1], 1, true) then return g[2] end end
  return nil
end

-- one parsed json file -> { name(lower case) = kind } for this level, or nil when the file is for another map or has nothing usable
function M.fromFile(c, level)
  if type(c) ~= 'table' or type(c.materials) ~= 'table' then return nil end
  local map = tostring(c.mapName or ''):lower()
  level = tostring(level or ''):lower()
  if not (map == '' or map == '*' or map == 'all' or (level ~= '' and level:find(map, 1, true))) then return nil end
  local out, any = {}, false
  for kind, names in pairs(c.materials) do
    if KIND[kind] and type(names) == 'table' then
      for _, nm in ipairs(names) do out[tostring(nm):lower()] = kind any = true end
    end
  end
  return any and out or nil
end

-- several files merged (a later file wins over an earlier one)
function M.merge(list, level)
  local out = {}
  for _, c in ipairs(list or {}) do
    local one = M.fromFile(c, level)
    if one then for k, v in pairs(one) do out[k] = v end end
  end
  return out
end

-- the game's own material name (particles.json: DIRT, GRAVEL, SAND, ASPHALT ...) -> a kind, or nil. idTable() holds only a map's extra ids, so this covers the stock ones.
function M.stockKind(name)
  local n = tostring(name or ''):lower()
  if n:find('snow') then return 'snow' end
  if n:find('ice') then return 'ice' end
  if n:find('mud') then return 'mud' end
  if n:find('sand') then return 'sand' end
  if n:find('gravel') or n:find('scree') then return 'gravel' end
  if n:find('grass') then return 'grass' end
  if n:find('dirt') or n:find('dust') then return 'dirt' end
  if n:find('asphalt') or n:find('concrete') or n:find('tarmac') then return 'tarmac' end
  return nil
end

-- name -> kind turned into collision-type id -> kind. groundModels = { NAME = { cdata = { collisiontype = id } } }; particleNames = { [id] = { name = 'DIRT' } } (the game's own materials).
-- knownIds: ids the car side already classifies by the game's own names (the fixed materials): the guess is only for ids beyond them.
-- Returns the table and a list of lines saying what was done (for the status).
function M.resolve(nameKind, groundModels, particleNames, knownIds)
  local out, notes = {}, {}
  for nm, kind in pairs(nameKind or {}) do
    local up, id = nm:upper(), nil
    local gm = groundModels and groundModels[up]
    if gm and gm.cdata then id = gm.cdata.collisiontype end
    if not id then for i, m in pairs(particleNames or {}) do if m.name == up then id = i break end end end
    if id then out[id] = kind notes[#notes + 1] = nm .. '=' .. kind .. '(' .. id .. ')' else notes[#notes + 1] = nm .. ' is no ground model or material here' end
  end
  for name, gm in pairs(groundModels or {}) do
    local id = gm.cdata and gm.cdata.collisiontype
    if id and out[id] == nil and not (knownIds and knownIds[id]) then
      local kind = M.guess(name)
      if kind then out[id] = kind notes[#notes + 1] = name .. '~' .. kind .. '(' .. id .. ')' end
    end
  end
  return out, notes
end

-- the Lua table text the car side takes: {[41]="sand",[42]="mud"}
function M.literal(idKind)
  local ids = {}
  for id in pairs(idKind or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  local parts = {}
  for i, id in ipairs(ids) do parts[i] = string.format('[%d]=%q', id, idKind[id]) end
  return '{' .. table.concat(parts, ',') .. '}'
end

-- ---- the game side: files, the level's ground models, a cache per level
local cache, cacheLevel, cacheNotes = nil, nil, {}

local function levelName()
  local s = ''
  pcall(function() s = (getMissionFilename and getMissionFilename()) or '' end)
  return tostring(s)
end

local function readFiles()
  local list = {}
  if not rawget(_G, 'FS') then return list end
  for _, folder in ipairs(M.FOLDERS) do
    local files = {}
    pcall(function() files = FS:findFiles(folder, '*.json', -1, true, false) or {} end)
    table.sort(files)
    for _, f in ipairs(files) do
      local ok, c = pcall(jsonReadFile, f)
      if ok and type(c) == 'table' then list[#list + 1] = c end
    end
  end
  return list
end

-- the id -> kind table of this level (cached; M.rescan() reads everything again)
function M.idTable()
  local level = levelName()
  if cache and cacheLevel == level then return cache end
  local particleNames = {}
  pcall(function() particleNames = require('particles').getMaterialsParticlesTable() end)
  local known = {}
  for id in pairs(particleNames) do known[id] = true end
  local gms = core_environment and core_environment.groundModels or {}
  cache, cacheNotes = M.resolve(M.merge(readFiles(), level), gms, particleNames, known)
  cacheLevel = level
  return cache
end
-- the kind of a ground by its collision-type id: a map's own entry, else the game's own material of that id (nil: unknown)
function M.kindOf(id)
  local k = M.idTable()[id]
  if k then return k end
  local ok, names = pcall(function() return require('particles').getMaterialsParticlesTable() end)
  local m = ok and names and names[id]
  return m and M.stockKind(m.name) or nil
end
function M.literalNow() return M.literal(M.idTable()) end
function M.notes() M.idTable() return cacheNotes end
function M.rescan() cache = nil return M.idTable() end

return M
