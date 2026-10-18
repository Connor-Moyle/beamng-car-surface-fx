-- Car Surface FX, vehicle side: ONE place that listens to the car's contacts and breaks, so body wear, sparks, debris and glass share it instead of each wrapping the game's calls.
--   carSurfaceFxContact.subscribe(name, function(ev) end)   name: any string (subscribing again with the same name replaces it); unsubscribe(name)
-- ev is a table that is REUSED for every event (copy what you need, never keep it):
--   a node collision: { kind = 'node', node, mat1, mat2, otherMat, perp, slip, speed, normalForce, x, y, z, nx, ny, nz, vx, vy, vz }
--     (x, y, z: the node's world position; nx, ny, nz: the surface normal, nz > 0.7 is ground; vx, vy, vz: the node's velocity; perp and slip m/s, normalForce N;
--      mat1 is this car's node material, mat2 (= otherMat) what it touched, the game's particles.json ids)
--   a beam break:     { kind = 'beam', beam, energy }
-- onNodeCollision is wrapped once, chain-safe (the previous handler runs first); onBeamBroke is the game's own extension hook. Every subscriber is called under pcall.
local M = {}

local subs, names = {}, {}                  -- subscribers in order
local ev = {}
local wrapped, active = false, false
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

local function wrapNodeCollision()
  if wrapped then return end
  wrapped = true
  local orig = onNodeCollision
  onNodeCollision = function(id1, pos, normal, nodeVel, perpVel, slipVec, slipVel, slipForce, normalForce, depth, m1, m2)
    if orig then orig(id1, pos, normal, nodeVel, perpVel, slipVec, slipVel, slipForce, normalForce, depth, m1, m2) end
    if not active or #subs == 0 then return end
    ev.kind, ev.node, ev.mat1, ev.mat2, ev.perp, ev.slip, ev.normalForce = 'node', id1, m1, m2, perpVel or 0, slipVel or 0, normalForce or 0
    ev.otherMat = m2
    ev.speed = nodeVel and math.sqrt((nodeVel.x or 0) ^ 2 + (nodeVel.y or 0) ^ 2 + (nodeVel.z or 0) ^ 2) or 0
    local ok, p = pcall(function() return obj:getAbsNodePosition(id1) end)
    if ok and p then ev.x, ev.y, ev.z = p.x, p.y, p.z else ev.x, ev.y, ev.z = 0, 0, 0 end
    local n, nv = normal, nodeVel
    ev.nx, ev.ny, ev.nz = n and n.x or 0, n and n.y or 0, n and n.z or 1
    ev.vx, ev.vy, ev.vz = nv and nv.x or 0, nv and nv.y or 0, nv and nv.z or 0
    ev.beam, ev.energy = nil, nil
    publish(ev)
  end
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
function M.onExtensionUnloaded() active = false subs, names = {}, {} end      -- the wrapper stays in the chain but does nothing

return M
