-- Car Surface FX, vehicle side: ONE place that listens to the car's contacts and breaks, so body wear, sparks, debris and glass share it instead of each wrapping the game's calls.
--   carSurfaceFxContact.subscribe(name, function(ev) end)   name: any string (subscribing again with the same name replaces it); unsubscribe(name)
-- (nx, ny, nz: the surface normal; slipDirX, slipDirY, slipDirZ: the sliding direction)
-- ev is a table that is REUSED for every event (copy what you need, never keep it):
--   a node collision: { kind = 'node', node, mat1, mat2, otherMat, perp, slip, speed, normalForce, x, y, z, nx, ny, nz, vx, vy, vz }
--     nodeMat is this car's node material and hitMat what it touched (worked out from the car's own node data, mat1 and mat2 are the game's two ids in the game's order);
--     (x, y, z: the node's world position; nx, ny, nz: the surface normal, nz > 0.7 is ground; vx, vy, vz: the node's velocity; perp and slip m/s, normalForce N;
--      the game's particles.json ids)
--   a beam break:     { kind = 'beam', beam, energy }
-- onNodeCollision is wrapped once, chain-safe (the previous handler runs first); onBeamBroke is the game's own extension hook. Every subscriber is called under pcall.
local M = {}

local subs, names = {}, {}                  -- subscribers in order
local ev = {}
local wrapped, active = false, false
local seen = { calls = 0, published = 0, maxPerp = 0, last = 0, via = 'not wrapped' }      -- for M.status(): does the game call onNodeCollision at all, and do hits get past the gate
local wheelNodes = nil

local function publish(e)
  for i = 1, #subs do pcall(subs[i], e) end
end

function M.subscribe(name, fn)
  if type(fn) ~= 'function' then return end
  for i, n in ipairs(names) do if n == name then subs[i] = fn return end end
  names[#names + 1], subs[#subs + 1] = name, fn
end
function M.unsubscribe(name)
  for i, n in ipairs(names) do if n == name then table.remove(names, i) table.remove(subs, i) return end end
end
function M.count() return #subs end
-- one line for the in-game check (vehicle console): carSurfaceFxContact.status()
function M.status() return string.format('tap %s, wrapped %s active %s subscribers %d | collisions seen %d, published %d, highest perp %.2f m/s, last %.2f', seen.via, tostring(wrapped), tostring(active), #subs, seen.calls, seen.published, seen.maxPerp, seen.last) end

-- the wheels' own nodes touch the ground all the time and are never a crash
local function isWheelNode(id)
  if not wheelNodes then
    local set = {}
    if wheels and wheels.wheels then
      for _, wd in pairs(wheels.wheels) do
        if wd.node1 then set[wd.node1] = true end
        if wd.node2 then set[wd.node2] = true end
        if wd.nodes then for _, n in pairs(wd.nodes) do set[n] = true end end
      end
    end
    if next(set) then wheelNodes = set else return false end
  end
  return wheelNodes[id] == true
end
M.isWheelNode = isWheelNode

-- what one node collision publishes (the numbers the game's own onNodeCollision gets)
local function handle(id1, pos, normal, nodeVel, perpVel, slipVec, slipVel, slipForce, normalForce, depth, m1, m2)
  seen.calls = seen.calls + 1 seen.last = perpVel or 0 if (perpVel or 0) > seen.maxPerp then seen.maxPerp = perpVel end
  if not active or #subs == 0 then return end
  ev.kind, ev.node, ev.mat1, ev.mat2, ev.perp, ev.slip, ev.normalForce = 'node', id1, m1, m2, perpVel or 0, slipVel or 0, normalForce or 0
  ev.otherMat = m2
  -- which of the two ids is this car's node and which is what it touched: the game's order is not what the first version of this file assumed (a tyre on asphalt arrived as
  -- asphalt, rubber). The car's own data says what the node is made of; without it the second id is the node's.
  local nd = v and v.data and v.data.nodes and v.data.nodes[id1]
  local nm = nd and tonumber(nd.nodeMaterial)
  if nm and (nm == m1 or nm == m2) then ev.nodeMat = nm else ev.nodeMat = m2 end
  ev.hitMat = (ev.nodeMat == m2) and m1 or m2
  if slipVec then ev.slipDirX, ev.slipDirY, ev.slipDirZ = slipVec.x, slipVec.y, slipVec.z else ev.slipDirX, ev.slipDirY, ev.slipDirZ = nil, nil, nil end   -- the sliding direction in the world
  ev.speed = nodeVel and math.sqrt((nodeVel.x or 0) ^ 2 + (nodeVel.y or 0) ^ 2 + (nodeVel.z or 0) ^ 2) or 0
  local ok, p = pcall(function() return obj:getAbsNodePosition(id1) end)
  if ok and p then ev.x, ev.y, ev.z = p.x, p.y, p.z else ev.x, ev.y, ev.z = 0, 0, 0 end
  local n, nv = normal, nodeVel
  ev.nx, ev.ny, ev.nz = n and n.x or 0, n and n.y or 0, n and n.z or 1
  ev.vx, ev.vy, ev.vz = nv and nv.x or 0, nv and nv.y or 0, nv and nv.z or 0
  ev.beam, ev.energy = nil, nil
  seen.published = seen.published + 1
  publish(ev)
end

-- the tap runs inside the game's own collision path: an error here must never reach it. The first error switches the tap off for this car, logged once.
local tapBroken = nil
local function safe(...)
  if tapBroken or not active then return end
  local ok, err = pcall(handle, ...)
  if not ok then tapBroken = tostring(err) seen.via = 'switched off after an error' pcall(log, 'E', 'carSurfaceFxContact', 'collision tap switched off: ' .. tapBroken) end
end

-- Where the game's collisions are tapped. The vehicle's main.lua onNodeCollision hands every collision to particlefilter.nodeCollision(p) (a table of the numbers), so wrapping that
-- module function is the surest tap (it does not matter how the engine finds the global). With no particlefilter the global onNodeCollision is wrapped instead. Chain-safe: the
-- previous handler always runs first. Once only.
local tapPf, tapOrig, tapWrapper                                -- what was wrapped, so unloading can put it back
local function wrapNodeCollision()
  if wrapped then return end
  wrapped = true
  local pf = rawget(_G, 'particlefilter')
  if pf and type(pf.nodeCollision) == 'function' then
    local orig = pf.nodeCollision
    tapWrapper = function(p, ...)
      orig(p, ...)
      if p then safe(p.id1, p.pos, p.normal, p.nodeVel, p.perpendicularVel, p.slipVec, p.slipVel, p.slipForce, p.normalForce, p.depth, p.materialID1, p.materialID2) end
    end
    pf.nodeCollision, tapPf, tapOrig = tapWrapper, pf, orig
    seen.via = 'particlefilter'
    return
  end
  local orig = onNodeCollision
  onNodeCollision = function(id1, pos, normal, nodeVel, perpVel, slipVec, slipVel, slipForce, normalForce, depth, m1, m2)
    if orig then orig(id1, pos, normal, nodeVel, perpVel, slipVec, slipVel, slipForce, normalForce, depth, m1, m2) end
    safe(id1, pos, normal, nodeVel, perpVel, slipVec, slipVel, slipForce, normalForce, depth, m1, m2)
  end
  seen.via = 'onNodeCollision'
end

-- the game calls this on every loaded vehicle extension when a beam breaks
function M.onBeamBroke(id, energy)
  if not active or #subs == 0 then return end
  ev.kind, ev.beam, ev.energy = 'beam', id, energy or 0
  ev.node, ev.mat1, ev.mat2, ev.otherMat, ev.perp, ev.slip, ev.speed, ev.normalForce, ev.x, ev.y, ev.z = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
  publish(ev)
end

-- subscribers turn the whole thing on while they have work to do
function M.setActive(on) active = on and true or false end

function M.onExtensionLoaded() wrapNodeCollision() end
function M.onReset() wheelNodes = nil end
function M.onExtensionUnloaded()
  active = false subs, names = {}, {}
  -- put the game's function back when ours is still the outermost; if something wrapped it after us the wrapper stays in the chain and does nothing
  if tapPf and tapPf.nodeCollision == tapWrapper then tapPf.nodeCollision = tapOrig wrapped = false end
  tapPf, tapOrig, tapWrapper = nil, nil, nil
end

return M
