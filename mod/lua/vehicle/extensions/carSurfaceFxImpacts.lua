-- Car Surface FX, vehicle side: crashes (port P9-P11). Listens through carSurfaceFxContact (the one shared wrapper) and tells the GE side (carSurfaceFx_impacts):
--   a window breaking (its beams fold into one cluster per pane) -> a pile of glass shards on the ground,
--   a joint giving way or a hard hit -> a few pieces of trim, plastic, metal or glass thrown off,
--   metal grinding on a hard surface -> a short burst of sparks.
-- The rules (which beams are windows, which materials make which pieces, which contacts spark) are in the GE side's impactrules.lua (tested); the vehicle side keeps the same small gates.
local M = {}
local random, floor = math.random, math.floor

local MAT = { METAL = 2, PLASTIC = 3, RUBBER = 4, GLASS = 5, WOOD = 6, ROCK = 13 }
local NO_SPARK = { [4] = true, [7] = true, [8] = true, [9] = true, [14] = true, [15] = true, [16] = true, [17] = true, [18] = true, [19] = true, [20] = true, [22] = true, [31] = true }

local cfg = { glass = false, debris = false, sparks = false, glassMinEnergy = 5, clusterRadius = 0.8, idle = 0.22, impactSpeed = 6.0, jointChance = 0.5, boltChance = 0.3,
  sparkMinSpeed = 3.0, sparkMinForce = 600 }
local clusters = {}
local simTime = 0
local nodeCooldown = {}
local sparkCooldown = {}
local subscribed = false
local lastBurst = 0

local function ge(cmd) pcall(function() obj:queueGameEngineLua(cmd) end) end

-- the wheels never throw debris: asked from the shared contact module
local function isWheel(id) return carSurfaceFxContact ~= nil and carSurfaceFxContact.isWheelNode(id) end

local function nodeMat(id)
  local nd = v and v.data and v.data.nodes and v.data.nodes[id]
  return nd and nd.nodeMaterial
end

local function classify(m1, m2)
  if m1 == MAT.RUBBER or m2 == MAT.RUBBER then return nil end
  if m1 == MAT.GLASS or m2 == MAT.GLASS then return 'glass' end
  if m1 == MAT.WOOD or m2 == MAT.WOOD then return 'wood' end
  if m1 == MAT.ROCK or m2 == MAT.ROCK then return 'rock' end
  if m1 == MAT.PLASTIC or m2 == MAT.PLASTIC then return 'plastic' end
  if random() < cfg.boltChance then return 'bolt' end
  return 'metal'
end

local function burst(nodeId, kind, hard, spread)
  local pos = obj:getPosition()
  local p = obj:getAbsNodePosition(nodeId)
  local nv = obj:getNodeVelocityVector(nodeId)
  ge(string.format('if carSurfaceFx_impacts then carSurfaceFx_impacts.debris(%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,"%s",%s,%.2f) end', obj:getId(), p.x, p.y, p.z, nv.x, nv.y, nv.z, kind, hard and 'true' or 'false', spread))
end

local function addToCluster(x, y, z)
  local r2 = cfg.clusterRadius * cfg.clusterRadius
  for _, c in ipairs(clusters) do
    local dx, dy, dz = x - c.x / c.n, y - c.y / c.n, z - c.z / c.n
    if dx * dx + dy * dy + dz * dz < r2 then c.x, c.y, c.z, c.n, c.last = c.x + x, c.y + y, c.z + z, c.n + 1, simTime return end
  end
  if #clusters < 12 then clusters[#clusters + 1] = { x = x, y = y, z = z, n = 1, last = simTime } end
end

local function onEvent(ev)
  if ev.kind == 'beam' then
    if (ev.energy or 0) < cfg.glassMinEnergy then return end
    local beam = v.data.beams and v.data.beams[ev.beam]
    if not beam then return end
    local m1, m2 = nodeMat(beam.id1), nodeMat(beam.id2)
    -- a window: both groups on the beam (the game's own sign of glass and wood), minus wood and plastic lenses
    if cfg.glass and beam.deformGroup and beam.breakGroup and m1 ~= MAT.WOOD and m2 ~= MAT.WOOD and m1 ~= MAT.PLASTIC and m2 ~= MAT.PLASTIC then
      local p = obj:getAbsNodePosition(beam.id1)
      addToCluster(p.x, p.y, p.z)
      return
    end
    if cfg.debris then
      local kind = classify(m1, m2)
      if kind and kind ~= 'glass' and random() <= cfg.jointChance then burst(beam.id1, kind, false, 0.1) end
    end
    return
  end
  -- a node collision
  local m1, m2 = ev.mat1, ev.mat2
  if cfg.sparks and ev.normalForce >= cfg.sparkMinForce and ev.slip >= cfg.sparkMinSpeed and (m1 == MAT.METAL or m2 == MAT.METAL) and not (NO_SPARK[m1] or NO_SPARK[m2]) then
    local t = simTime
    if (sparkCooldown[ev.node] or 0) <= t then
      sparkCooldown[ev.node] = t + 0.08
      local nv = obj:getNodeVelocityVector(ev.node)
      ge(string.format('if carSurfaceFx_impacts then carSurfaceFx_impacts.sparks(%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.0f) end', ev.x, ev.y, ev.z, nv.x, nv.y, nv.z, ev.normalForce))
    end
  end
  if cfg.debris and ev.perp >= cfg.impactSpeed and m1 ~= MAT.RUBBER and m2 ~= MAT.RUBBER and not isWheel(ev.node) then
    local t = simTime
    if (nodeCooldown[ev.node] or 0) <= t then
      nodeCooldown[ev.node] = t + 0.5
      local kind = classify(m1, m2)
      if kind then burst(ev.node, kind, true, 0.15) end
    end
  end
end

local function ensureSubscribed()
  if subscribed then return end
  if not carSurfaceFxContact then pcall(extensions.load, 'carSurfaceFxContact') end
  if carSurfaceFxContact then
    carSurfaceFxContact.subscribe('impacts', onEvent)
    carSurfaceFxContact.setActive(true)
    subscribed = true
  end
end

function M.setConfig(glass, debris, sparks, t)
  cfg.glass, cfg.debris, cfg.sparks = glass and true or false, debris and true or false, sparks and true or false
  if type(t) == 'table' then for k, val in pairs(t) do if cfg[k] ~= nil and type(val) == 'number' then cfg[k] = val end end end
  if cfg.glass or cfg.debris or cfg.sparks then ensureSubscribed() end
end

local function frame(dt)
  simTime = simTime + dt
  if #clusters == 0 then return end
  local i = 1
  while i <= #clusters do
    local c = clusters[i]
    if simTime - c.last >= cfg.idle then
      local sev = c.n >= 20 and 1 or 0.3 + 0.7 * (c.n / 20)
      ge(string.format('if carSurfaceFx_impacts then carSurfaceFx_impacts.glass(%d,%.3f,%.3f,%.3f,%.2f) end', obj:getId(), c.x / c.n, c.y / c.n, c.z / c.n, sev))
      table.remove(clusters, i)
    else
      i = i + 1
    end
  end
end

-- a test: every window beam of this car breaks through the engine's own call, so the whole chain runs (the break, the detection, the pile). Returns how many beams.
function M.breakWindows()
  local n = 0
  for _, beam in pairs(v.data.beams or {}) do
    local m1, m2 = nodeMat(beam.id1), nodeMat(beam.id2)
    if beam.deformGroup and beam.breakGroup and m1 ~= MAT.WOOD and m2 ~= MAT.WOOD and m1 ~= MAT.PLASTIC and m2 ~= MAT.PLASTIC and beam.cid then
      pcall(function() obj:breakBeam(beam.cid) end)
      n = n + 1
    end
  end
  return n
end

function M.updateGFX(dt) pcall(frame, dt or 0) end
function M.onReset() clusters = {} nodeCooldown, sparkCooldown = {}, {} end
function M.onExtensionUnloaded() clusters = {} if carSurfaceFxContact then carSurfaceFxContact.unsubscribe('impacts') end subscribed = false end

return M
