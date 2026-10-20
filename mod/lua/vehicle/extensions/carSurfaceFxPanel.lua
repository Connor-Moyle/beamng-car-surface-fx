-- Car Surface FX, vehicle side: panel damage (docs/PANEL_DAMAGE.md). Listens through carSurfaceFxContact (the one shared wrapper) for a body node hitting something and tells the
-- GE side (carSurfaceFx_paneldamage.hit): which node, how fast it hit, how hard it pressed, and the car's mass and node count (the energy is worked out there, in panelrules.lua).
-- Metal and plastic nodes (fibreglass and carbon come from the panel's material, a later step). The same small gates as the other effects: a per-node cooldown, no wheels, no rubber.
local M = {}

local MAT = { METAL = 2, PLASTIC = 3, RUBBER = 4 }
local byMat = {}                                    -- at-speed hits by the car's node material, for status()

local cfg = { enabled = false, minPerp = 1.0, cooldown = 0.4 }
local nodeReady = {}
local subscribed = false
local mass, nodes
local seen = { events = 0, nodeEv = 0, sent = 0, rejMat = 0, rejSlow = 0, rejWheel = 0, rejCool = 0, hardMat1 = nil, hardMat2 = nil, hardN = 0 }      -- for M.status()

local function ge(cmd) pcall(function() obj:queueGameEngineLua(cmd) end) end

local function carNumbers()
  if mass then return end
  mass, nodes = 0, 0
  local d = v and v.data and v.data.nodes
  if not d then return end
  for _, n in pairs(d) do nodes = nodes + 1 mass = mass + (tonumber(n.nodeWeight) or 0) end
end

local function onEvent(ev)
  seen.events = seen.events + 1
  if not cfg.enabled or ev.kind ~= 'node' then return end
  seen.nodeEv = seen.nodeEv + 1
  if ev.perp >= cfg.minPerp then seen.hardN = seen.hardN + 1 seen.hardMat1, seen.hardMat2 = ev.nodeMat, ev.hitMat byMat[ev.nodeMat or -1] = (byMat[ev.nodeMat or -1] or 0) + 1 end          -- the materials of the last hit at speed, for status()
  if ev.perp < cfg.minPerp then seen.rejSlow = seen.rejSlow + 1 return end
  -- rubber nodes count too (bumper covers and trim are often rubber in the jbeam): the wheel check below keeps the tyres out
  if (ev.nodeMat ~= MAT.METAL and ev.nodeMat ~= MAT.PLASTIC and ev.nodeMat ~= MAT.RUBBER) or ev.hitMat == MAT.RUBBER then seen.rejMat = seen.rejMat + 1 return end
  if carSurfaceFxContact and carSurfaceFxContact.isWheelNode and carSurfaceFxContact.isWheelNode(ev.node) then seen.rejWheel = seen.rejWheel + 1 return end
  local t = os.clock()
  if (nodeReady[ev.node] or 0) > t then seen.rejCool = seen.rejCool + 1 return end
  nodeReady[ev.node] = t + cfg.cooldown
  seen.sent = seen.sent + 1
  carNumbers()
  ge(string.format('if carSurfaceFx_paneldamage then carSurfaceFx_paneldamage.hit(%d, %d, %.2f, %.0f, %.0f, %d, %d) end', obj:getId(), ev.node, ev.perp, ev.normalForce, mass, nodes, ev.nodeMat))
end

local function ensureSubscribed()
  if subscribed then return end
  if not carSurfaceFxContact then pcall(extensions.load, 'carSurfaceFxContact') end
  if carSurfaceFxContact then
    carSurfaceFxContact.subscribe('panel', onEvent)
    carSurfaceFxContact.setActive(true)
    subscribed = true
  end
end

-- the GE side sets the switch and the speed under which a hit is ignored
function M.setConfig(enabled, minPerp)
  cfg.enabled = enabled and true or false
  if tonumber(minPerp) then cfg.minPerp = tonumber(minPerp) end
  if cfg.enabled then ensureSubscribed() end
end

-- one line for the in-game check (vehicle console): carSurfaceFxPanel.status()
function M.status() local h = {} for k, n in pairs(byMat) do h[#h + 1] = k .. ':' .. n end table.sort(h) return string.format('at speed by node material {%s} | ', table.concat(h, ' ')) .. string.format('enabled %s subscribed %s minPerp %.2f | events %d, node events %d, sent to the game %d | rejected: too slow %d, material %d, wheel %d, cooldown %d | hits at speed %d, last node material %s, hit %s', tostring(cfg.enabled), tostring(subscribed), cfg.minPerp, seen.events, seen.nodeEv, seen.sent, seen.rejSlow, seen.rejMat, seen.rejWheel, seen.rejCool, seen.hardN, tostring(seen.hardMat1), tostring(seen.hardMat2)) end

function M.onReset() nodeReady = {} end
function M.onExtensionUnloaded() if carSurfaceFxContact then pcall(carSurfaceFxContact.unsubscribe, 'panel') end subscribed = false end

return M
