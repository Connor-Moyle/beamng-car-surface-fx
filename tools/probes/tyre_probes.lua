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
  return 'info() | api() | friction(wheelIdx) | frictionRestore() | thermal(wheelIdx) | thermalRead(wheelIdx) | collisionStart() | collisionRead() | materials() | switchWheelMaterial(wheelIdx, matName) | resetMaterials() | sparks(wheelIdx) | sparksRestore(wheelIdx) | clearLog() | dump()'
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

return P
