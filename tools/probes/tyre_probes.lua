-- Tyre simulation, build step 1: the PROBES (docs/TYRE_WEAR_RESEARCH.md section 9.2). Vehicle Lua, to be run on the PLAYER's car through the MCP tool run_lua_vehicle
-- (or the in-game vehicle Lua console). It changes nothing permanently except what a probe says: every probe that writes has a restore, and a vehicle reset (Ctrl+R / R) undoes the rest.
-- Nothing here is a mod. It answers: can we do this, and what do the numbers look like, so the mod is built on facts. See tools/probes/README.md for the order and what to look at.
--
-- Load it:   run_lua_vehicle with the whole file as the code (it defines the global CSFXP and returns the list of commands).
-- Then each command is a one-line run_lua_vehicle call that returns text, e.g.  return CSFXP.info()
-- Every call is wrapped in pcall; an error comes back as the text "ERR: ...", which is an answer too (the API is not what the research thought).

CSFXP = CSFXP or {}
local P = CSFXP
P.log = P.log or {}
local function say(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end local s = table.concat(t, ' ') P.log[#P.log + 1] = s return s end
local function try(name, f, ...)
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return say(name, '->', a, b, c, d) end
  return say(name, 'ERR:', a)
end
local function wd(i) return wheels and wheels.wheels and wheels.wheels[i] end
local function wheelList() local out = {} for i, w in pairs(wheels.wheels) do out[#out + 1] = i end table.sort(out) return out end
local function nodeData(cid) return v and v.data and v.data.nodes and v.data.nodes[cid] end

function P.commands()
  return 'info() | api() | friction(wheelIdx) | frictionRestore() | thermal(wheelIdx) | thermalRead(wheelIdx) | collisionStart() | collisionRead() | materials() | switchWheelMaterial(wheelIdx, matName) | resetMaterials() | sparks(wheelIdx) | sparksRestore(wheelIdx) | forceTry(wheelIdx, N) | forceRead() | clearLog() | dump()'
end
function P.clearLog() P.log = {} return 'cleared' end
function P.dump() return table.concat(P.log, '\n') end

-- ---- 0. what the car has: wheels, tread nodes, radius, friction, pressure
function P.info()
  P.log = {}
  say('wheels:', #wheelList(), 'physics dt', obj.getPhysicsDt and obj:getPhysicsDt() or 'n/a')
  for _, i in ipairs(wheelList()) do
    local w = wd(i)
    say(string.format('wheel %s name=%s treadNodes=%s radius=%s treadCoef=%s softness=%s noLoad=%s pressureGroup=%s startPsi=%s deflated=%s', tostring(i), tostring(w.name),
      tostring(w.treadNodes and #w.treadNodes), tostring(w.radius), tostring(w.treadCoef), tostring(w.softnessCoef), tostring(w.noLoadCoef), tostring(w.pressureGroupId),
      tostring(w.startingPressure), tostring(w.isTireDeflated)))
    if w.treadNodes then
      local first = w.treadNodes[1]
      local nd = nodeData(first)
      say('  first tread node', first, 'frictionCoef', nd and nd.frictionCoef, 'slidingFrictionCoef', nd and nd.slidingFrictionCoef, 'nodeMaterial', nd and (nd.nodeMaterial or nd.nm))
    end
  end
  return P.dump()
end

-- ---- 0b. which bindings exist at all on this build (the unproven ones from the research)
function P.api()
  P.log = {}
  for _, n in ipairs({ 'setNodeFrictionSlidingCoefs', 'getNodeFrictionCoef', 'getNodeSlidingFrictionCoef', 'setNodeMaterial', 'getSlipPower', 'getSlipEnergy', 'getWheelAvgTemperature',
    'getWheelCoreTemperature', 'getNodeTemperature', 'setNodeTemperature', 'setWheelCoreTemperature', 'getWheelAirTemperature', 'switchMaterial', 'resetMaterials', 'getSwitchableMaterial',
    'setMaterialOverride', 'setMaterialRemap', 'setMaterialParameter', 'addParticleVelWidthTypeCount', 'getGroupPressure', 'getEnvPressure', 'getEnvTemperature', 'applyForce', 'setNodeMass' }) do
    say('obj.' .. n, type(obj[n]))
  end
  local w = wd(wheelList()[1])
  say('wd.obj', type(w and w.obj), 'wd.obj.setThermal', type(w and w.obj and w.obj.setThermal), 'wd.obj.setFrictionThermalSensitivity', type(w and w.obj and w.obj.setFrictionThermalSensitivity))
  say('particles', type(particles), 'getMaterialIDByName', type(particles and particles.getMaterialIDByName), 'controller', type(controller), 'loadControllerExternal', type(controller and controller.loadControllerExternal))
  say('wheels.nodeCollision', type(wheels and wheels.nodeCollision), 'wheels.updateGFX', type(wheels and wheels.updateGFX))
  return P.dump()
end

-- ---- 1. per-node friction set/read (probe a): halve the tread friction of one wheel, read it back. Then: drive / push the car and see that corner slide (or run the car on a flat road, handbrake turn)
P.saved = P.saved or {}
function P.friction(i)
  P.log = {}
  local w = wd(i)
  if not (w and w.treadNodes) then return 'no wheel ' .. tostring(i) end
  for k, cid in ipairs(w.treadNodes) do
    local nd = nodeData(cid)
    if nd and not (P.saved[cid]) then P.saved[cid] = { nd.frictionCoef, nd.slidingFrictionCoef } end
  end
  local cid1 = w.treadNodes[1]
  try('read before getNodeFrictionCoef', function() return obj:getNodeFrictionCoef(cid1) end)
  try('read before getNodeSlidingFrictionCoef', function() return obj:getNodeSlidingFrictionCoef(cid1) end)
  for _, cid in ipairs(w.treadNodes) do
    local b = P.saved[cid]
    if b then pcall(function() obj:setNodeFrictionSlidingCoefs(cid, b[1] * 0.5, b[2] * 0.5) end) end
  end
  try('read after getNodeFrictionCoef (expect half of the base)', function() return obj:getNodeFrictionCoef(cid1) end)
  try('read after getNodeSlidingFrictionCoef', function() return obj:getNodeSlidingFrictionCoef(cid1) end)
  say('base was', P.saved[cid1] and P.saved[cid1][1], P.saved[cid1] and P.saved[cid1][2], ' -> now the wheel has HALF the tread grip. Drive: that corner should slip. frictionRestore() puts it back')
  return P.dump()
end
function P.frictionRestore()
  local n = 0
  for cid, b in pairs(P.saved) do pcall(function() obj:setNodeFrictionSlidingCoefs(cid, b[1], b[2]) end) n = n + 1 end
  return 'restored ' .. n .. ' nodes'
end

-- ---- 2. the native thermal model at runtime (probe e). Argument order from stage2.lua:282-299. The coefficients are GUESSES (units unknown): the point is to see a reading move
function P.thermal(i)
  P.log = {}
  local w = wd(i)
  if not (w and w.obj) then return 'no wheel ' .. tostring(i) end
  local o = w.obj
  try('setThermal', function()
    return o:setThermal(0.5, 0.4, 20, 0.2, 0.2, 0.2, 0.0005, 0.0005, 0.0003, 1e18, 1e19, false)
  end)
  try('setFrictionThermalSensitivity', function()
    return o:setFrictionThermalSensitivity(40, 90, 0.01, 0.01, 10, 0.8, 1, 0.85)
  end)
  say('now do a burnout (or hard cornering) and call thermalRead(' .. tostring(i) .. ') every few seconds: the temperatures should rise')
  return P.thermalRead(i, true)
end
function P.thermalRead(i, keep)
  if not keep then P.log = {} end
  local w = wd(i)
  if not w then return 'no wheel' end
  local id = w.wheelID or i
  try('getWheelAvgTemperature', function() return obj:getWheelAvgTemperature(id) end)
  try('getWheelCoreTemperature', function() return obj:getWheelCoreTemperature(id) end)
  try('getNodeTemperature(tread 1)', function() return obj:getNodeTemperature(w.treadNodes[1]) end)
  try('getNodeTemperature(tread 2)', function() return obj:getNodeTemperature(w.treadNodes[2]) end)
  say('slip', w.lastSlip, 'slipEnergy', w.slipEnergy, 'downForce', w.downForce, 'lastTreadContactNode', w.lastTreadContactNode, 'env C', obj.getEnvTemperature and (obj:getEnvTemperature() - 273.15))
  return P.dump()
end

-- ---- 3. nodeCollision: how many calls per second, which fields, and how much it costs. Wraps wheels.nodeCollision if the engine reaches it through the wheels module.
function P.collisionStart()
  P.log = {}
  P.col = { calls = 0, t0 = os.clock(), nodes = {}, sample = nil, cpu = 0 }
  if P.colWrapped then return 'already counting' end
  local orig = wheels.nodeCollision
  if type(orig) ~= 'function' then return 'wheels.nodeCollision is ' .. type(orig) end
  wheels.nodeCollision = function(p, ...)
    local c = P.col
    local t = os.clock()
    c.calls = c.calls + 1
    if p then
      if p.id1 then c.nodes[p.id1] = (c.nodes[p.id1] or 0) + 1 end
      if not c.sample then c.sample = string.format('id1=%s slipVel=%s slipForce=%s normalForce=%s mat1=%s mat2=%s', tostring(p.id1), tostring(p.slipVel), tostring(p.slipForce), tostring(p.normalForce), tostring(p.materialID1), tostring(p.materialID2)) end
    end
    c.cpu = c.cpu + (os.clock() - t)
    return orig(p, ...)
  end
  P.colWrapped = true
  P.colOrig = orig
  return 'counting: drive for 20 s (include a burnout and a locked skid), then collisionRead()'
end
function P.collisionRead()
  local c = P.col
  if not c then return 'collisionStart() first' end
  local secs = os.clock() - c.t0
  local distinct = 0 for _ in pairs(c.nodes) do distinct = distinct + 1 end
  return string.format('calls %d in %.1f s = %.0f/s; %d distinct nodes; our counting cost %.2f ms/s; sample: %s', c.calls, secs, c.calls / math.max(secs, 0.001), distinct, c.cpu / math.max(secs, 0.001) * 1000, tostring(c.sample))
end

-- ---- 4. material switching per wheel (probe c): which meshes the tyres use, and whether ONE tyre can change on its own
function P.materials()
  P.log = {}
  local seen = {}
  for _, fb in pairs(v.data.flexbodies or {}) do
    local nm = tostring(fb.mesh or fb.meshName or fb.name or '?')
    if nm:lower():find('tire') or nm:lower():find('wheel') then
      say('flexbody', nm, 'idx', tostring(fb.__index or fb.idx or ''), 'group', tostring(fb.group and table.concat(fb.group, ',') or ''), 'material', tostring(fb.mapTo or fb.material or ''))
    end
  end
  say('Same mesh name on two lines (FL and FR) = shared mesh: a per-mesh switch changes both tyres.')
  return P.dump()
end
function P.switchWheelMaterial(i, mat)
  P.log = {}
  mat = mat or 'tire_01a_old'
  local w = wd(i)
  say('wheel', i, w and w.name)
  -- the jbeam way: per mesh
  for _, fb in pairs(v.data.flexbodies or {}) do
    local nm = tostring(fb.mesh or fb.meshName or '')
    local g = fb.group and table.concat(fb.group, ',') or ''
    if nm:lower():find('tire') and w and w.name and g:find(tostring(w.name)) then
      try('getSwitchableMaterial ' .. nm, function()
        local msc = obj:getSwitchableMaterial('tire_01a', mat, nm)
        local r = obj:switchMaterial(msc, mat)
        return msc, r
      end)
    end
  end
  say('look at the car: did ONLY wheel', i, 'change, or the other tyre of the axle too? Take a screenshot. resetMaterials() puts it back.')
  return P.dump()
end
function P.resetMaterials()
  P.log = {}
  try('resetMaterials', function() return obj:resetMaterials(0) end)
  return P.dump()
end

-- ---- 5. sparks: set a few tread nodes of a wheel to METAL, then burnout / slide on asphalt: do sparks and a metal sound appear
function P.sparks(i)
  P.log = {}
  local w = wd(i)
  if not (w and w.treadNodes) then return 'no wheel' end
  local id
  try('getMaterialIDByName(METAL)', function() id = particles.getMaterialIDByName(particles.materials or v.data.materials, 'METAL') return id end)
  if not id then id = 2 say('falling back to id 2 (METAL in the research)') end
  P.metalBefore = P.metalBefore or {}
  for k = 1, math.min(4, #w.treadNodes) do
    local cid = w.treadNodes[k]
    local nd = nodeData(cid)
    P.metalBefore[cid] = nd and (nd.nodeMaterialId or nd.nodeMaterial) or 4
    try('setNodeMaterial ' .. cid, function() return obj:setNodeMaterial(cid, id) end)
  end
  say('now slide / burnout on this wheel on asphalt: sparks? scraping sound? Does the car handle differently? sparksRestore(' .. tostring(i) .. ') puts RUBBER (4) back')
  return P.dump()
end
function P.sparksRestore(i)
  local w = wd(i)
  if not (w and w.treadNodes) then return 'no wheel' end
  for k = 1, math.min(4, #w.treadNodes) do pcall(function() obj:setNodeMaterial(w.treadNodes[k], 4) end) end
  return 'rubber back on 4 nodes'
end

-- ---- 6. fire and smoke (docs: fire.lua in the game). fire.lua only burns nodes that have a flashPoint in the jbeam, and pops a tyre when its HUB nodes (node1/node2) pass tirePopTemp = 650 C.
-- Tread nodes have no flashPoint, so a tyre fire is ours: the particles below on a tread node, then beamstate.deflateTire at the end. These probes check each piece.
function P.fireInfo()
  P.log = {}
  try('fire module', function() return fire ~= nil end)
  try('flammable nodes', function() local n = 0 for _ in pairs(fire.debugData.flammableNodes or {}) do n = n + 1 end return n end)
  try('igniteNode exists', function() return type(fire.igniteNode) end)
  try('deflateTire exists', function() return type(beamstate.deflateTire) end)
  try('addParticleByNodesRelative exists', function() return type(obj.addParticleByNodesRelative) end)
  return P.dump()
end
-- fire/smoke particles on one tread node for a moment: ids from fire.lua (25/27/29 flames, 51/52 smoke). Look at the wheel, then screenshot.
function P.fireParticles(i, id, count)
  P.log = {}
  local w = wd(i)
  if not (w and w.treadNodes) then return 'no wheel' end
  local cid = w.treadNodes[1]
  try('particle ' .. tostring(id or 27), function() return obj:addParticleByNodesRelative(cid, w.node1, 0, id or 27, 0.5, count or 20) end)
  say('call again (every 0.1 s from a loop) to keep it going; ids tried so far are in the log')
  return P.dump()
end
-- is the fire table writable: inject a flammable entry for a tread node, so the game itself heats and burns it? (it is a hack: only worth it if particles alone look bad)
function P.fireInject(i)
  P.log = {}
  local w = wd(i)
  if not (w and w.treadNodes) then return 'no wheel' end
  local cid = w.treadNodes[1]
  try('inject', function()
    local fl = fire.debugData.flammableNodes
    fl[cid] = { name = 'csfx_tread', flashPoint = 350, smokePoint = 200, burnRate = 0.05, staticBaseTemp = 20, useThermalsBaseTemp = false, conductionRadius = 0, selfIgnitionCoef = 0,
      temperature = 20, intensity = 0, chemEnergy = 2000, originalChemEnergy = 2000, weightSpecHeatCoef = 0.2, lastUnderWaterValue = 0, flameTick = 0, smokeTick = 0, vaporState = 0,
      isVapor = 0, containerBeamCache = nil, ignoreContainerBeamBreakMessage = true, containerBeamBroken = false, canIgnite = true }
    return 'injected ' .. cid
  end)
  try('igniteNode', function() fire.igniteNode(cid, 400) return 'ignited at 400' end)
  say('watch the wheel for flames/smoke for ~10 s. Tread nodes are not wheel hub nodes, so the tyre should NOT pop on its own. fireClear() puts it out and removes the entry')
  P.fireCid = cid
  return P.dump()
end
function P.fireClear()
  local cid = P.fireCid
  pcall(function() fire.debugData.flammableNodes[cid] = nil end)
  pcall(function() fire.extinguishVehicle() end)
  return 'cleared'
end
-- pop one tyre the way the rules would after a long fire (reset the car to undo it)
function P.fireDeflate(i) return select(2, pcall(function() beamstate.deflateTire(i, 1) return 'deflated wheel ' .. i end)) end
-- debris: which particle ids give small dark bits? Throws one id at a time from the rear tread node, backwards. Try 1..60 in turn and note the ones that look like rubber/dirt chunks.
function P.debrisParticle(i, id)
  local w = wd(i)
  if not (w and w.treadNodes) then return 'no wheel' end
  local ok, err = pcall(function() obj:addParticleByNodesRelative(w.treadNodes[1], w.node1, -4, id, 0.5, 30) end)
  return ok and ('id ' .. id .. ' sent') or ('ERR: ' .. tostring(err))
end

-- the fallback if fireInject does not work: light the flammable car node nearest to the wheel (the game's fire then spreads from it)
function P.fireNearest(i)
  P.log = {}
  local w = wd(i)
  if not (w and w.node1) then return 'no wheel' end
  try('nearest flammable', function()
    local p0 = v.data.nodes[w.node1].pos
    local best, bd
    for cid in pairs(fire.debugData.flammableNodes or {}) do
      local n = v.data.nodes[cid]
      if n and not (w.treadNodes and cid == w.treadNodes[1]) then
        local d = (n.pos.x - p0.x) ^ 2 + (n.pos.y - p0.y) ^ 2 + (n.pos.z - p0.z) ^ 2
        if not bd or d < bd then best, bd = cid, d end
      end
    end
    if not best then return 'no flammable car nodes' end
    fire.igniteNode(best, 600)
    return 'lit node ' .. best .. ' at ' .. string.format('%.2f m', math.sqrt(bd))
  end)
  say('watch 20 s: does it spread through the car? fireClear() / reset the car to put it out')
  return P.dump()
end

-- ---- f8. the signature of the force calls, for the physical flat-spot shake (research 8.6, level 3). Each variant is tried in its own pcall and the car is asked to say whether it moved:
-- applyForce(n1, n2, F) is the one stock code uses (playerController: a force along the line between two nodes); applyForceTime and applyForceVector are the others.
-- Run on a car standing still on a flat road: forceTry(wheelIdx, N) pulls the first tread node toward its hub for ONE physics step per call, forceBurst(wheelIdx, N, steps) repeats it
-- for `steps` calls in a row from the vehicle's updateGFX (so: a frame each). Read the node's position before and after with forceRead. A reset (R) undoes any damage.
function P.forceTry(i, newtons)
  P.log = {}
  local w = wd(i)
  if not (w and w.treadNodes and w.node1) then return 'no wheel ' .. tostring(i) end
  local cid, hub, F = w.treadNodes[1], w.node1, newtons or 200
  P.fPos0 = obj:getNodePosition(cid)
  try('applyForce(treadCid, hubCid, F)', function() return obj:applyForce(cid, hub, F) end)
  try('applyForceTime(treadCid, hubCid, F, 0.05)', function() return obj:applyForceTime(cid, hub, F, 0.05) end)
  try('applyForceVector(treadCid, vec3)', function() return obj:applyForceVector(cid, vec3(0, 0, -F)) end)
  say('node', cid, 'before', tostring(P.fPos0), '-> forceRead() after a second')
  return P.dump()
end
function P.forceRead()
  local cid = nil
  for _, i in ipairs(wheelList()) do cid = wd(i).treadNodes[1] break end
  return 'node moved ' .. tostring(P.fPos0 and cid and (obj:getNodePosition(cid) - P.fPos0):length()) .. ' m (before ' .. tostring(P.fPos0) .. ')'
end

-- ---- 7. blowout damages the panels near it (f7). Pops wheel i, then (if hit) pushes the nearest body nodes outward over 3 physics steps. Drive at 0 / 50 / 100 km/h, run it, screenshot the arch before and after.
-- Safe by construction: force capped at 3000 N per node, never the wheel's own nodes, 3 nodes. Reset the car afterwards (R).
function P.blowout(i, newtons)
  P.log = {}
  local w = wd(i)
  if not (w and w.treadNodes) then return 'no wheel' end
  local f = math.min(newtons or 1500, 3000)
  local skip = {}
  for _, cid in ipairs(w.treadNodes) do skip[cid] = true end
  skip[w.node1], skip[w.node2] = true, true
  for _, wd2 in pairs(wheels.wheels) do skip[wd2.node1], skip[wd2.node2] = true, true for _, c in ipairs(wd2.treadNodes or {}) do skip[c] = true end end
  local centre = v.data.nodes[w.node1].pos
  local list = {}
  for cid, n in pairs(v.data.nodes) do
    if not skip[cid] and n.pos and not n.fixed and not n.couplerTag and not tostring(n.group or ''):lower():find('wheel') and not tostring(n.group or ''):lower():find('susp') and not tostring(n.group or ''):lower():find('hub') then
      local dx, dy, dz = n.pos.x - centre.x, n.pos.y - centre.y, n.pos.z - centre.z
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d <= 0.55 then list[#list + 1] = { cid = cid, d = d, dx = dx / d, dy = dy / d, dz = dz / d * 0.5 } end
    end
  end
  table.sort(list, function(a, b) return a.d < b.d end)
  say('body nodes in 0.55 m of the wheel (not wheel nodes):', #list)
  P.blowTargets = {}
  for k = 1, math.min(3, #list) do P.blowTargets[k] = list[k] end
  P.blowSteps = 3 P.blowForce = f
  try('deflateTire', function() beamstate.deflateTire(i) return 'popped' end)
  return P.dump()
end
-- call this from updateGFX-like ticks; here: a one-off helper that applies one step. Call it 3 times in a row (3 run_lua_vehicle calls, or loop with CSFXP.blowoutApply(3))
function P.blowoutApply(times)
  local n = 0
  for _ = 1, math.min(times or 1, P.blowSteps or 0) do
    for _, t in ipairs(P.blowTargets or {}) do
      if pcall(function() obj:applyForceVector(t.cid, vec3(t.dx * P.blowForce, t.dy * P.blowForce, t.dz * P.blowForce)) end) then n = n + 1 end
    end
    P.blowSteps = P.blowSteps - 1
  end
  if (P.blowSteps or 0) <= 0 then P.blowTargets = {} end
  return 'applied ' .. n .. ' pushes'
end

return P
