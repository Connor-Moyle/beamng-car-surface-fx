-- Car Surface FX: debug tools for the console (port P16). Nothing here is in the player's interface and nothing runs until it is asked for:
--   carSurfaceFx.debugTools()            loads this and returns the list of commands
--   carSurfaceFx_debug.counts()          how many marks, puddles, glass piles, ruts ... are alive
--   carSurfaceFx_debug.status()          every module's own status line
--   carSurfaceFx_debug.contacts(true)    a marker at each wheel's contact point of the player's car
--   carSurfaceFx_debug.surfaces(true)    the ground kind, game material, load and slip written at each wheel
--   carSurfaceFx_debug.clearAll()        takes every mark, puddle, piece of glass, rut ... off the ground
--   carSurfaceFx_debug.testAll()         puts one of each effect down in front of the car
--   carSurfaceFx_debug.logging(true)     more log lines from the modules that have a switch for it
local M = {}
local TAG = 'carSurfaceFx_debug'

local MODULES = { 'carSurfaceFx_marks', 'carSurfaceFx_fluids', 'carSurfaceFx_impacts', 'carSurfaceFx_ruts', 'carSurfaceFx_grass', 'carSurfaceFx_scratch' }
local showContacts, showSurfaces = false, false
local seen = {}                                   -- vehicle id -> { wheels = {...}, at = clock }

local function mod(n) return rawget(_G, n) end
local function try(f, ...) local ok, r = pcall(f, ...) return ok and r or ('error: ' .. tostring(r)) end

function M.help() return 'counts() status() contacts(on) surfaces(on) clearAll() testAll() logging(on) help()' end

function M.counts()
  local out = {}
  local m = mod('carSurfaceFx_marks')
  if m then out[#out + 1] = string.format('marks: skid %d track %d', m.count('skid'), m.count('track')) end
  local f = mod('carSurfaceFx_fluids')
  if f then out[#out + 1] = 'puddles: ' .. tostring(try(f.count)) end
  local i = mod('carSurfaceFx_impacts')
  if i then out[#out + 1] = 'impacts: ' .. tostring(try(i.status)) end
  local r = mod('carSurfaceFx_ruts')
  if r then out[#out + 1] = 'ruts: ' .. tostring(try(r.status)) end
  local g = mod('carSurfaceFx_grass')
  if g and g.status then out[#out + 1] = 'grass: ' .. tostring(try(g.status)) end
  if #out == 0 then return 'no effect module is running' end
  return table.concat(out, '\n')
end

function M.status()
  local out = {}
  local main = mod('carSurfaceFx')
  if main then out[#out + 1] = 'main: ' .. tostring(try(main.status)) end
  for _, n in ipairs(MODULES) do
    local m = mod(n)
    if m and m.status then out[#out + 1] = n:gsub('^carSurfaceFx_', '') .. ': ' .. tostring(try(m.status)) end
  end
  return table.concat(out, '\n')
end

function M.clearAll()
  local n = 0
  for _, name in ipairs(MODULES) do
    local m = mod(name)
    if m and m.clear then pcall(m.clear) n = n + 1 end
  end
  return 'cleared ' .. n .. ' modules'
end

function M.testAll()
  local m = mod('carSurfaceFx_impacts')
  if m and m.test then for _, w in ipairs({ 'glass', 'debris', 'sparks' }) do pcall(m.test, w) end end
  local r = mod('carSurfaceFx_ruts')
  if r and r.test then pcall(r.test, 'mud', 2) end
  return 'one of each effect put down in front of the car'
end

function M.logging(on)
  for _, name in ipairs(MODULES) do
    local m = mod(name)
    if m and m.setDebug then pcall(m.setDebug, on and true or false) end
  end
  return 'verbose logging ' .. (on and 'on' or 'off')
end

-- ---- the wheel reports from the player's car
local function pushOn(v, flag)
  v:queueLuaCommand('if not carSurfaceFxDebug then extensions.load("carSurfaceFxDebug") end carSurfaceFxDebug.setOn(' .. (flag and 'true' or 'false') .. ')')
  local ok, lit = pcall(function() return require('carSurfaceFx/surfaces').literalNow() end)
  if flag and ok and lit and lit ~= '{}' then v:queueLuaCommand('carSurfaceFxDebug.setMaterials(' .. lit .. ')') end
end
local function pushAll()
  local flag = showContacts or showSurfaces
  local pv = be:getPlayerVehicleID(0)
  for _, v in ipairs(getAllVehicles()) do
    if v:getID() == pv or not flag then pcall(pushOn, v, flag) end
  end
end
function M.contacts(on) showContacts = on and true or false pushAll() return 'contact markers ' .. (showContacts and 'on' or 'off') end
function M.surfaces(on) showSurfaces = on and true or false pushAll() return 'surface labels ' .. (showSurfaces and 'on' or 'off') end

function M.wheels(id, list) seen[id] = { wheels = list, at = os.clock() } end

local KIND_COLOUR = { mud = { 0.55, 0.35, 0.15 }, snow = { 0.9, 0.95, 1 }, sand = { 0.9, 0.8, 0.45 }, dirt = { 0.65, 0.45, 0.25 }, gravel = { 0.6, 0.6, 0.6 }, grass = { 0.2, 0.8, 0.2 },
  ice = { 0.5, 0.9, 1 }, water = { 0.2, 0.4, 1 }, asphalt = { 0.35, 0.35, 0.35 }, concrete = { 0.5, 0.5, 0.5 }, rock = { 0.45, 0.4, 0.4 }, metal = { 0.7, 0.7, 0.8 } }

function M.onPreRender()
  if not (showContacts or showSurfaces) or not debugDrawer then return end
  local now = os.clock()
  for id, s in pairs(seen) do
    if now - s.at > 1 then seen[id] = nil
    else
      for _, w in ipairs(s.wheels) do
        local pos = vec3(w[2], w[3], w[4])
        local c = KIND_COLOUR[w[6]] or { 1, 0, 1 }
        if showContacts then debugDrawer:drawSphere(pos, 0.08 + math.min(w[7], 6000) / 60000, ColorF(c[1], c[2], c[3], 0.9)) end
        if showSurfaces then
          debugDrawer:drawTextAdvanced(pos + vec3(0, 0, 0.35), String(string.format('%s (%s) %.0f N slip %.1f', w[6], w[5], w[7], w[8])), ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 0, 160))
        end
      end
    end
  end
end

function M.onVehicleSpawned() if showContacts or showSurfaces then pcall(pushAll) end end
function M.onExtensionUnloaded() showContacts, showSurfaces = false, false pcall(pushAll) seen = {} end
function M.onClientEndMission() seen = {} end

M.TAG = TAG
require('carSurfaceFx/guard').wrap(M, TAG, { 'onPreRender' })
return M
