-- Car Surface FX: panel damage (extension carSurfaceFx_paneldamage; docs/PANEL_DAMAGE.md). A hit on a body panel is drawn as a dent in the car's paint canvases
-- (carSurfaceFx_scratch.dent). Thin slice: metal dents only, off by default. The car side (carSurfaceFxPanel) reports hits; this works out the energy and the size (panelrules.lua,
-- tested), and draws. The API for other code (the tyre blowout): damageAt / damageNode / clear, and the probe hooks for the in-game check.
local M = {}

local rules = require('carSurfaceFx/panelrules')

local TAG = 'carSurfaceFx_paneldamage'
local settings = rules.defaults()
local counts = { hits = 0, drawn = 0, tooSoft = 0, noMap = 0 }
local lastHit                                       -- the last hit seen, for the probe: { cid, perp, force, E, sev }
local topLog = {}                                    -- the 10 hardest hits since the log was switched on
local hitLog = {}                                   -- the probe's log of hits: { perp, force, mass, nodes, E, sev }
local logOn = false
local readyAt = {}                                  -- vehId .. ':' .. cid -> os.clock() when the node may be marked again

local function scratch() return rawget(_G, 'carSurfaceFx_scratch') end
local function now() return os.clock() end

function M.defaults() return rules.defaults() end
function M.settings() return settings end

-- t = the panel part of the main settings file ({ enabled, metal, amount, minEnergy, maxMarks }); the cars are told the switch
function M.configure(t)
  settings = rules.defaults()
  for k, v in pairs(type(t) == 'table' and t or {}) do if settings[k] ~= nil and type(v) == type(settings[k]) then settings[k] = v end end
  pcall(function()
    for _, veh in ipairs(getAllVehicles()) do
      veh:queueLuaCommand(string.format('if not carSurfaceFxPanel then extensions.load("carSurfaceFxPanel") end carSurfaceFxPanel.setConfig(%s, 1.0)', settings.enabled and 'true' or 'false'))
    end
  end)
end

-- the car side's report of a body node that hit something
function M.hit(vid, cid, perp, force, mass, nodes, nodeMaterial, dv)
  counts.hits = counts.hits + 1
  local E = rules.energy(rules.closingSpeed(perp, dv), force, mass, nodes)
  local sev = rules.severity(E, settings.minEnergy)
  lastHit = { cid = cid, perp = perp, force = force, E = E, sev = sev }
  if logOn then
    local r = { perp = perp, force = force, mass = mass, nodes = nodes, E = E, sev = sev, dv = dv }
    hitLog[#hitLog + 1] = r
    if #hitLog > 200 then table.remove(hitLog, 1) end
    topLog[#topLog + 1] = r                         -- the hardest hits seen, kept apart (the last ones are the resting rattle against the wall)
    table.sort(topLog, function(a, b) return a.E > b.E end)
    while #topLog > 10 do table.remove(topLog) end
  end
  local kind = rules.kindOf({ nodeMaterial = nodeMaterial })
  local key = tostring(vid) .. ':' .. tostring(cid)
  if not rules.accept(settings, kind, E, now(), readyAt[key]) then counts.tooSoft = counts.tooSoft + 1 return false end
  readyAt[key] = now() + 0.4
  return M.damageNode(vid, cid, E, kind)
end

-- the API: a dent on node cid of car vid for a hit of energyJ joules. kind and dir are optional (kind: 'metal' (paint chips), 'plastic', 'fibreglass' or 'carbon'; dir is not used yet).
function M.damageNode(vid, cid, energyJ, kind, dir)
  if not settings.enabled then return false end
  kind = kind or rules.kindOf(nil)
  if not rules.KINDS[kind] or settings[kind] ~= true then return false end
  local sc = scratch()
  if not sc then counts.noMap = counts.noMap + 1 return false end
  local sev = rules.severity(energyJ, settings.minEnergy)
  if sev <= 0 then counts.tooSoft = counts.tooSoft + 1 return false end
  local ok = sc.dent(vid, cid, sev, rules.radius(sev, settings.amount), settings.maxMarks, rules.LIGHT, kind)
  if ok then counts.drawn = counts.drawn + 1 else counts.noMap = counts.noMap + 1 end
  return ok
end

-- a dent at a world position: the nearest node the car's paint map knows (within 0.4 m)
function M.damageAt(vid, worldPos, energyJ, kind, dir)
  if not settings.enabled then return false end
  local sc = scratch()
  local cid = sc and sc.nearestNode and sc.nearestNode(vid, worldPos, 0.4)
  if not cid then return false end
  return M.damageNode(vid, cid, energyJ, kind, dir)
end

function M.clear(vid)
  local sc = scratch()
  if sc and sc.repair then sc.repair(vid) end
end

-- ---- the probe hooks (docs/PANEL_DAMAGE.md section 7), for the in-game check ----------------------------------------------------------------------------------------------
-- (each takes a last argument, the kind: 'metal' (default), 'plastic', 'fibreglass', 'carbon')
-- carSurfaceFx_paneldamage.probe('dent', sev)         a test mark on the mapped node nearest the car's centre, 0.9 m up; sev 0.1 .. 1 (default 0.6)
-- carSurfaceFx_paneldamage.probe('row', n)            n dents (default 10) along the car's length, 0.9 m out to the side and 0.7 m up (a 4th argument sets the height in metres, 0.45 is the door skin): the position and seam check
-- carSurfaceFx_paneldamage.probe('fill', n)           n dents on mapped nodes (default 40), for the cost check: watch the frame time
-- carSurfaceFx_paneldamage.probe('log', true|false)   record the real hits (speed, force, mass, energy, depth); status() lists the last ones
-- carSurfaceFx_paneldamage.probe('info')              does the player car's paint have a palette and the lit page (a black car shows the marks only with one of them)
-- carSurfaceFx_paneldamage.probe('clear')
-- Each returns a line of text. The master switch must be on first (Mods menu > Panel damage).
function M.probe(what, arg, kind, kind2)
  kind = kind or 'metal'
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  if what == 'log' then logOn = arg ~= false hitLog = {} topLog = {} return 'hit log ' .. (logOn and 'on' or 'off') end
  if what == 'info' then
    local sc0 = scratch()
    local pi = veh and sc0 and sc0.paintInfo and sc0.paintInfo(veh:getId())
    if not pi then return 'no paint canvases on the player car' end
    return string.format('paint bound %s, canvases %s, palette %s (false: marks can only darken), lit page %s (true needs Mods > Dirt > Lit snow)', tostring(pi.bound), tostring(pi.canvas), tostring(pi.palette), tostring(pi.lit))
  end
  if what == 'clear' then if veh then M.clear(veh:getId()) end return 'cleared' end
  if not veh then return 'no player vehicle' end
  local sc = scratch()
  if not sc then return 'carSurfaceFx_scratch is not loaded (switch Scratches on)' end
  if not settings.enabled then return 'panel damage is off' end
  local id = veh:getId()
  local sev = math.max(0.1, math.min(1, tonumber(arg) or 0.6))
  local E = settings.minEnergy * rules.SPAN ^ ((sev - 0.1) / 0.9)
  if what == 'dent' then
    local pos = veh:getPosition() + vec3(0, 0, 0.9)
    local cid, d = sc.nearestNode(id, pos, 3)
    if not cid then return 'no mapped node near the car centre (does the car have a source .dae?)' end
    return 'dent on node ' .. cid .. string.format(' (%.2f m away) depth %.2f: ', d or 0, sev) .. tostring(M.damageNode(id, cid, E, kind))
  elseif what == 'row' then
    local n, drawn = math.floor(tonumber(arg) or 10), 0
    local rowH = tonumber(kind2) or 0.7
    local dir, up = veh:getDirectionVector(), vec3(0, 0, 1)
    local side = dir:cross(up):normalized()
    local c = veh:getPosition()
    for i = 0, n - 1 do
      local p = c + dir * (-2 + 4 * i / math.max(1, n - 1)) + side * 0.9 + up * rowH
      local cid = sc.nearestNode(id, p, 0.6)
      if cid and M.damageNode(id, cid, settings.minEnergy * 6, kind) then drawn = drawn + 1 end
    end
    return 'row: ' .. drawn .. ' of ' .. n .. ' dents drawn'
  elseif what == 'fill' then
    local n, drawn = math.floor(tonumber(arg) or 40), 0
    local list = sc.mappedNodes and sc.mappedNodes(id) or {}
    for i = 1, n do
      local cid = list[1 + (i * 7919) % math.max(1, #list)]
      if cid and M.damageNode(id, cid, settings.minEnergy * 6, kind) then drawn = drawn + 1 end
    end
    return 'fill: ' .. drawn .. ' of ' .. n .. ' dents drawn; ' .. sc.dentCount(id) .. ' on the car'
  end
  return 'unknown probe ' .. tostring(what)
end

function M.status()
  local function line(r) return string.format('node perp %.1f m/s, car speed change %.1f m/s, force %.0f N, mass %.0f kg, %d nodes -> %.0f J, depth %.2f', r.perp, r.dv or -1, r.force, r.mass, r.nodes, r.E, r.sev) end
  local rows, top = {}, {}
  for i = math.max(1, #hitLog - 4), #hitLog do rows[#rows + 1] = line(hitLog[i]) end
  for _, r in ipairs(topLog) do top[#top + 1] = line(r) end
  return { enabled = settings.enabled, metal = settings.metal, plastic = settings.plastic, fibreglass = settings.fibreglass, carbon = settings.carbon, counts = counts, last = lastHit, hardest = top, latest = rows }
end

function M.onVehicleSpawned() M.configure(settings) end
function M.onClientEndMission() readyAt = {} end
function M.onExtensionUnloaded()
  pcall(function() for _, veh in ipairs(getAllVehicles()) do veh:queueLuaCommand('if carSurfaceFxPanel then carSurfaceFxPanel.setConfig(false) end') end end)
end

require('carSurfaceFx/guard').wrap(M, TAG, { 'hit' })
return M
