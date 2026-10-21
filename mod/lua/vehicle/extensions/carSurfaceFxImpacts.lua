-- Car Surface FX, vehicle side: crashes (port P9-P11). Listens through carSurfaceFxContact (the one shared wrapper) and tells the GE side (carSurfaceFx_impacts):
--   a window breaking (its beams fold into one cluster per pane) -> a pile of glass shards on the ground,
--   a joint giving way or a hard hit -> a few pieces of trim, plastic, metal or glass thrown off,
--   metal grinding on a hard surface -> a short burst of sparks.
-- The rules (which beams are windows, which materials make which pieces, which contacts spark) are in the GE side's impactrules.lua (tested); the vehicle side keeps the same small gates.
local M = {}
local random, floor, min, max = math.random, math.floor, math.min, math.max

local MAT = { METAL = 2, PLASTIC = 3, RUBBER = 4, GLASS = 5, WOOD = 6, ROCK = 13 }
local NO_SPARK = { [4] = true, [7] = true, [8] = true, [9] = true, [14] = true, [15] = true, [16] = true, [17] = true, [18] = true, [19] = true, [20] = true, [22] = true, [31] = true }

local cfg = { glass = false, debris = false, sparks = false, glassMinEnergy = 5, clusterRadius = 0.8, idle = 0.22, impactSpeed = 6.0, jointChance = 0.5, boltChance = 0.3,
  sparkMinSpeed = 3.0, sparkMinForce = 600, sparkAmount = 1.0, debrisAmount = 1.0, particles = 1 }

-- the game's own particle emitters (BNGP_<n>, the same numbers lua/vehicle/beamstate.lua and lua/common/particles.json use); kept equal to the GE side's impactrules.PARTICLE by the test
M.PARTICLE = { metal = { 1 }, bolt = { 1 }, plastic = { 56, 57, 58 }, glass = { 68, 69 }, wood = { 12 }, rock = { 2 } }
local SPARK = 9                                         -- BNGP_9 (sparks explosion: 10-15 cm, 15 m/s) instead of the game's BNGP_1 (4-12 cm, 1 m/s), which is not visible by day at Low
local function particleFor(kind) local l = M.PARTICLE[kind] or M.PARTICLE.metal return l[1 + floor(random() * #l) % #l] end
local clusters = {}
local simTime = 0
local probeUntil = 0                                          -- breakWindows (a test) waives the energy gate for a moment: a beam broken from Lua carries no energy
local nodeCooldown = {}
local sparkCooldown = {}
local subscribed = false

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

-- throw `count` of the game's particles from a node: along the surface normal (or up) carrying the node's velocity
local function throw(node, nx, ny, nz, vx, vy, vz, ptype, count, speed, width)
  if count < 1 then return end
  pcall(function() obj:addParticleVelWidthTypeCount(node, vec3(nx, ny, nz), vec3(vx, vy, vz), speed, width, ptype, count) end)
end

local function burst(nodeId, kind, hard, spread)
  local pos = obj:getPosition()
  local p = obj:getAbsNodePosition(nodeId)
  local nv = obj:getNodeVelocityVector(nodeId)
  if cfg.particles == 1 and kind ~= 'glass' then      -- (a breaking window is the game's own glass particles already)
    throw(nodeId, 0, 0, 1, nv.x, nv.y, nv.z, particleFor(kind), floor((hard and 2 or 1) * cfg.debrisAmount + 0.5), 1.0, 0.1)
  end
  ge(string.format('if carSurfaceFx_impacts then carSurfaceFx_impacts.debris(%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,"%s",%s,%.2f) end', obj:getId(), p.x, p.y, p.z, nv.x, nv.y, nv.z, kind, hard and 'true' or 'false', spread))
end

-- the same rule as the GE side's impactrules.isGlassBeam: a group that says glass (roofglass_break), not wood, plastic or lamp glass
local function isGlassBeam(beam, m1, m2)
  if not (beam.deformGroup or beam.breakGroup) or m1 == MAT.WOOD or m2 == MAT.WOOD or m1 == MAT.PLASTIC or m2 == MAT.PLASTIC then return false end
  local g = (tostring(beam.deformGroup or '') .. ' ' .. tostring(beam.breakGroup or '')):lower()
  if g:find('light', 1, true) or g:find('lamp', 1, true) then return false end
  if m1 == MAT.GLASS or m2 == MAT.GLASS then return true end
  return g:find('glass', 1, true) ~= nil or g:find('window', 1, true) ~= nil or g:find('windshield', 1, true) ~= nil or g:find('windscreen', 1, true) ~= nil
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
    if (ev.energy or 0) < cfg.glassMinEnergy and simTime > probeUntil then return end
    local beam = v.data.beams and v.data.beams[ev.beam]
    if not beam then return end
    local m1, m2 = nodeMat(beam.id1), nodeMat(beam.id2)
    -- a window: a group named glass on the beam (see isGlassBeam)
    if cfg.glass and isGlassBeam(beam, m1, m2) then
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
  local m1, m2 = ev.nodeMat, ev.hitMat                      -- the car's node and what it touched (the contact module works the game's id order out)
  if cfg.sparks and ev.normalForce >= cfg.sparkMinForce and ev.slip >= cfg.sparkMinSpeed and m1 == MAT.METAL and not NO_SPARK[m2] then
    local t = simTime
    if (sparkCooldown[ev.node] or 0) <= t then
      sparkCooldown[ev.node] = t + 0.08
      -- the game's own spark particle (the one it uses for metal on asphalt), a few more for a harder scrape
      throw(ev.node, ev.nx, ev.ny, ev.nz, ev.vx, ev.vy, ev.vz, SPARK, max(1, floor((1 + min(ev.normalForce, 6000) / 2000) * cfg.sparkAmount + 0.5)), 1.0, 0.1)
      ge('if carSurfaceFx_impacts then carSurfaceFx_impacts.sparks() end')
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
      ge(string.format('if carSurfaceFx_impacts then carSurfaceFx_impacts.glass(%d,%.3f,%.3f,%.3f,%.2f,%d) end', obj:getId(), c.x / c.n, c.y / c.n, c.z / c.n, sev, c.n))
      table.remove(clusters, i)
    else
      i = i + 1
    end
  end
end

-- a test: the effects thrown from the car's front by hand (the game's own particles): 'sparks' or 'debris'
function M.test(what)
  local n = 1
  for _, nd in pairs(v.data.nodes or {}) do
    n = nd.cid or n
    break
  end
  if what == 'sparks' then for _ = 1, 8 do throw(n, 0, 0, 1, 0, 0, 0, SPARK, 3, 1.0, 0.1) end
  else
    for kind in pairs(M.PARTICLE) do throw(n, 0, 0, 1, 0, 0, 0, particleFor(kind), 3, 1.0, 0.1) end
  end
  return what
end

-- a test: every window beam of this car breaks through the engine's own call, so the whole chain runs (the break, the detection, the pile). Returns how many beams.
function M.breakWindows()
  local n = 0
  probeUntil = simTime + 3
  for _, beam in pairs(v.data.beams or {}) do
    local m1, m2 = nodeMat(beam.id1), nodeMat(beam.id2)
    if isGlassBeam(beam, m1, m2) and beam.cid then
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
