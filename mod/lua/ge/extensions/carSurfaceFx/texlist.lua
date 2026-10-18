-- Car Surface FX: the pictures a player can drop into a folder (port P13). A folder under art/decals holds white-on-transparent pngs; the ones whose name starts with a prefix are the
-- variants of one effect (puddles, glass shards, debris chips). The Mods menu's texture-tile field lists the folder (the registry rescans it when the page opens); the choice is a file name,
-- or nothing for "any of them, at random". Pure picking, tested by tests/texlist_test.lua.
local M = {}

-- the names (without the folder) of the pngs in `dir` whose name starts with `prefix`, sorted. FS is the game's file system (nothing without it: the caller uses its defaults)
function M.scan(dir, prefix)
  local out = {}
  if not rawget(_G, 'FS') then return out end
  local files = {}
  pcall(function() files = FS:findFiles('/' .. dir, '*.png', 0, true, false) or {} end)
  prefix = (prefix or ''):lower()
  for _, f in ipairs(files) do
    local name = tostring(f):match('([^/\\]+)$')
    if name and name:lower():sub(1, #prefix) == prefix then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- which file: `choice` (a name, or '' for any) out of `list`, by a 0..1 seed. A choice that is not in the list falls back to any. nil for an empty list.
function M.pick(list, choice, seed)
  if not list or #list == 0 then return nil end
  if choice and choice ~= '' then
    local want = tostring(choice):match('([^/\\]+)$'):lower()
    for _, name in ipairs(list) do if name:lower() == want then return name end end
  end
  return list[1 + math.floor((seed or 0) * #list) % #list]
end

-- the list a draw loop walks: only the chosen file when one is chosen (and there), else all of them
function M.shown(list, choice)
  if choice and choice ~= '' then
    local one = M.pick(list, choice, 0)
    local want = tostring(choice):match('([^/\\]+)$'):lower()
    if one and one:lower() == want then return { one } end
  end
  return list or {}
end

-- which of the shown files a thing with this seed is drawn with (index into M.shown)
function M.indexFor(n, seed) return n > 0 and (1 + math.floor((seed or 0) * n) % n) or 0 end

return M
