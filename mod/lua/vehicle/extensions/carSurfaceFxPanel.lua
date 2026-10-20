-- Car Surface FX, vehicle side: panel damage (docs/PANEL_DAMAGE.md). Listens through carSurfaceFxContact (the one shared wrapper) for a body node hitting something and tells the
-- GE side (carSurfaceFx_paneldamage.hit): which node, how fast it hit, how hard it pressed, and the car's mass and node count (the energy is worked out there, in panelrules.lua).
-- Metal and plastic nodes (fibreglass and carbon come from the panel's material, a later step). The same small gates as the other effects: a per-node cooldown, no wheels, no rubber.
local M = {}

local MAT = { METAL = 2, PLASTIC = 3, RUBBER = 4 }

local cfg = { enabled = false, minPerp = 1.0, cooldown = 0.4 }
local nodeReady = {}
local subscribed = false
local mass, nodes

local function ge(cmd) pcall(function() obj:queueGameEngineLua(cmd) end) end

local function carNumbers()
  if mass then return end
  mass, nodes = 0, 0
  local d = v and v.data and v.data.nodes
  if not d then return end
  for _, n in pairs(d) do nodes = nodes + 1 mass = mass + (tonumber(n.nodeWeight) or 0) end
end

local function onEvent(ev)
  if not cfg.enabled or ev.kind ~= 'node' then return end
  if (ev.mat1 ~= MAT.METAL and ev.mat1 ~= MAT.PLASTIC) or ev.mat2 == MAT.RUBBER or ev.perp < cfg.minPerp then return end
  if carSurfaceFxContact and carSurfaceFxContact.isWheelNode and carSurfaceFxContact.isWheelNode(ev.node) then return end
  local t = os.clock()
  if (nodeReady[ev.node] or 0) > t then return end
  nodeReady[ev.node] = t + cfg.cooldown
  carNumbers()
  ge(string.format('if carSurfaceFx_paneldamage then carSurfaceFx_paneldamage.hit(%d, %d, %.2f, %.0f, %.0f, %d, %d) end', obj:getId(), ev.node, ev.perp, ev.normalForce, mass, nodes, ev.mat1))
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

function M.onReset() nodeReady = {} end
function M.onExtensionUnloaded() if carSurfaceFxContact then pcall(carSurfaceFxContact.unsubscribe, 'panel') end subscribed = false end

return M
