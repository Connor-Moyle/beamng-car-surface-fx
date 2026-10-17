-- Wrench Works: puts a group of controls into the game's own Options page (the layout file /ui/ui-vue/src/modules/options/runtime/layout.json), shared by the
-- mods that add one (graphics, car surface effects). Each mod has its own marker; the group carries it as "_slrr":"<marker>" and is found, replaced and
-- taken out again by it, so two mods' groups live side by side in the one user-folder copy of the layout.
--
-- Use (from a mod's extension, on load):
--   local L = require('slrr/optionsLayout')
--   L.install({ marker = 'surfacefx-v1', group = groupTable, after = 'GraphicAntialiasType', log = function(level, msg) log(level, 'mymod', msg) end })
--   ...and on deactivation: L.uninstall('surfacefx-v1')
-- The group table is plain data in the game's own item format (see slrr/graphics.lua optionsGroup(): itemType 'group', component 'OptionsGroup', with its items);
-- its "_slrr" field is filled in here. Settings the items name are ordinary game settings (settings.getValue/setValue; onSettingsChanged is called on changes).
-- The page only reads the file when the UI loads it, so the first time the game has to be restarted once.
local M = {}

M.LAYOUT_DIR = '/ui/ui-vue/src/modules/options/runtime/'

-- our group as JSON text (written by hand: the game's encoder cannot tell an empty list from an empty object, and the layout is full of empty lists)
local function encodeJson(v)
  local t = type(v)
  if t == 'string' then
    local escaped = v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' elseif c == '\n' then return '\\n' end
      return string.format('\\u%04x', c:byte())
    end)
    return '"' .. escaped .. '"'
  elseif t == 'number' or t == 'boolean' then return tostring(v)
  elseif t == 'table' then
    if next(v) == nil or v[1] ~= nil then
      local out = {}
      for i = 1, #v do out[i] = encodeJson(v[i]) end
      return '[' .. table.concat(out, ',') .. ']'
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = encodeJson(k) .. ':' .. encodeJson(v[k]) end
    return '{' .. table.concat(out, ',') .. '}'
  end
  return 'null'
end
M.encodeJson = encodeJson

-- where the object that opens at text[open] ends (strings skipped); nil if the text runs out
local function objectEnd(text, open)
  local depth, pos = 0, open
  while true do
    local i = text:find('["{}]', pos)
    if not i then return nil end
    local c = text:sub(i, i)
    if c == '"' then
      local j = i + 1
      while true do
        j = text:find('["\\]', j)
        if not j then return nil end
        if text:sub(j, j) == '\\' then j = j + 2 else break end
      end
      pos = j + 1
    elseif c == '{' then
      depth = depth + 1
      pos = i + 1
    else
      depth = depth - 1
      if depth == 0 then return i end
      pos = i + 1
    end
  end
end
M.objectEnd = objectEnd

-- the text without the group that begins with `start` (a plain string such as ',{"_slrr":"x"'); nil if the text is unbalanced
local function stripStart(text, start)
  local at = text:find(start, 1, true)
  if not at then return text end
  local close = objectEnd(text, at + 1)
  if not close then return nil end
  return text:sub(1, at - 1) .. text:sub(close + 1)
end

-- the text without the group of one marker (`legacy`: extra start strings of earlier versions of that group)
function M.strip(text, marker, legacy)
  local starts = { ',{"_slrr":' .. M.encodeJson(marker) }
  for _, l in ipairs(legacy or {}) do starts[#starts + 1] = l end      -- (the game's Lua has no table.unpack)
  for _, start in ipairs(starts) do
    text = stripStart(text, start)
    if not text then return nil end
  end
  return text
end

-- the text without any group of ours, whichever mod it belongs to
function M.stripAll(text)
  while true do
    local at = text:find(',{"_slrr":"', 1, true)
    if not at then return text end
    local close = objectEnd(text, at + 1)
    if not close then return nil end
    text = text:sub(1, at - 1) .. text:sub(close + 1)
  end
end

-- the group put into the text right after the item with `"setting":"<after>"`, the rest of the text untouched (byte for byte). nil + reason if it cannot.
function M.insertAfter(text, after, group)
  local anchor = text:find('"setting"%s*:%s*"' .. after .. '"')
  if not anchor then return nil, 'the page has no ' .. after .. ' item to put the group after' end
  local json = encodeJson(group)
  -- walk the text (strings skipped) to find the object that holds the anchor and where it ends
  local pos, stack, itemStart, depthAtItem = 1, {}, nil, nil
  while true do
    local i = text:find('["{}]', pos)
    if not i then return nil, 'unbalanced layout' end
    local c = text:sub(i, i)
    if c == '"' then
      local j = i + 1
      while true do
        j = text:find('["\\]', j)
        if not j then return nil, 'unbalanced layout' end
        if text:sub(j, j) == '\\' then j = j + 2 else break end
      end
      pos = j + 1
    elseif c == '{' then
      stack[#stack + 1] = i
      pos = i + 1
    else
      table.remove(stack)
      if itemStart and #stack < depthAtItem then
        return text:sub(1, i) .. ',' .. json .. text:sub(i + 1)
      end
      pos = i + 1
    end
    if not itemStart and pos > anchor then
      itemStart = stack[#stack]
      depthAtItem = #stack
    end
  end
end

-- (marker's old group out, new one in; `legacy` as in strip)
function M.patchText(text, marker, group, after, legacy)
  if type(text) ~= 'string' then return nil, 'no layout' end
  text = M.strip(text, marker, legacy)
  if not text then return nil, 'unbalanced layout' end
  group._slrr = marker
  return M.insertAfter(text, after, group)
end

local function slash(p) return (string.gsub(p or '', '\\', '/')) end

local function readText(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local text = f:read('*a')
  f:close()
  return text
end

local function inUserFolder(real)
  local user = slash(FS:getUserPath())
  return user ~= '' and string.sub(slash(real), 1, #user) == user
end

-- the game's own layout text, from wherever it is: its real file (when that is not the copy in the user folder), the game folder, or the game's virtual file
-- system (which shows the user folder copy once there is one). Second result: where it came from (or what was tried).
function M.gameText()
  local vpath = M.LAYOUT_DIR .. 'layout.json'
  local real = slash(FS:getFileRealPath(vpath))
  local candidates = {}
  if real ~= '' and not inUserFolder(real) then candidates[#candidates + 1] = real end
  candidates[#candidates + 1] = slash(FS:getGamePath()) .. vpath
  for _, path in ipairs(candidates) do
    local text = readText(path)
    if text and #text > 1000 then return text, path end
  end
  local ok, text = pcall(readFile, vpath)
  if ok and type(text) == 'string' and #text > 1000 then return M.stripAll(text) or text, 'virtual ' .. vpath end
  return nil, 'real=' .. real .. ' game=' .. slash(FS:getGamePath())
end

-- opts: marker, group (table), after (setting name), legacy (optional), log (function(level, message))
function M.install(opts)
  local log = opts.log or function() end
  local ok, err = pcall(function()
    local game, source = M.gameText()
    if not game then log('W', 'options page: the game layout file was not found (' .. tostring(source) .. '), nothing added') return end
    -- the user-folder copy holds other mods' groups as well; it is only a base while it is the game's layout plus groups of ours (a game update makes it stale)
    local mine = slash(FS:getFileRealPath(M.LAYOUT_DIR .. 'layout.json'))
    local current = inUserFolder(mine) and readText(mine) or nil
    local base = game
    if current and M.stripAll(current) == game then base = current end
    local patched, why = M.patchText(base, opts.marker, opts.group, opts.after, opts.legacy)
    if not patched then log('W', 'options page: ' .. tostring(why) .. ' (read from ' .. tostring(source) .. '), nothing changed') return end
    if current == patched then return end
    extensions.load('ui_options')
    if ui_options.saveLayout('', patched) then
      log('I', 'options page: group ' .. opts.marker .. ' added, layout read from ' .. tostring(source) .. ' (restart the game to see it if the page was already open)')
    end
  end)
  if not ok then log('E', 'options page install failed: ' .. tostring(err)) end
end

-- takes one mod's group away again; the user-folder copy goes when no group of ours is left in it
function M.uninstall(marker, legacy)
  local real = slash(FS:getFileRealPath(M.LAYOUT_DIR .. 'layout.json'))
  if not inUserFolder(real) then return end
  local text = readText(real)
  local rest = text and M.strip(text, marker, legacy)
  if rest and rest:find(',{"_slrr":"', 1, true) then
    extensions.load('ui_options')
    ui_options.saveLayout('', rest)
  else
    FS:removeFile(real)
  end
end

return M
