-- Ported from Enhanced Skid Marks (Surface FX) by Fatkiwi (the same author), renamed for Car Surface FX.
--[[ ------------------------------------------------------------------------
  carSurfaceFxScratch.lua  -  per-car: REPORTS hard sliding body hits. nothing else.
  by Fatkiwi (ported from Enhanced Skid Marks' dirtScratchHiFi.lua)

  all the work (where a node sits on the paint texture, the canvases, the drawing)
  lives GE-side in carSurfaceFx/scratch.lua + carSurfaceFx/meshuv.lua, because that is
  the side that can read the car's mesh and own its textures. this file only knows what
  the GE side can't see: a body node just slid hard against something.
  detection wraps onNodeCollision, as the original mod does.
------------------------------------------------------------------------- --]]

local M = {}

local RUBBER_MAT = 4
local FORCE_MIN  = 1500
local SLIP_MIN   = 1.5
local COOLDOWN   = 0.12          -- s between marks PER node
local CAR_GAP    = 0.02          -- s between marks for the whole car: a big crash can't flood the GE queue


local enabled = false                  -- pushed from the GE side
local DEBUG = false

local wheelNodes     = nil
local nodeCooldown   = {}
local nextHitT       = 0
local _wrapped       = false

local function buildWheelNodes()
  local set = {}
  if wheels and wheels.wheels then
    for _, wd in pairs(wheels.wheels) do
      if wd.node1 then set[wd.node1] = true end
      if wd.node2 then set[wd.node2] = true end
      if wd.nodes then for _, n in pairs(wd.nodes) do set[n] = true end end
    end
  end
  return set
end

-- a world-space direction as components along the car's own ref->left / ref->back / ref->up
-- node lines. the GE side knows those same three lines at rest, so no axis convention is assumed.
local function alongRefs(s)
  local r = v.data.refNodes and v.data.refNodes[0]
  if not r then return 0, 0, 0 end
  local p0 = obj:getNodePosition(r.ref)
  local function along(n)
    local p = obj:getNodePosition(n)
    local ax, ay, az = p.x - p0.x, p.y - p0.y, p.z - p0.z
    local l = math.sqrt(ax * ax + ay * ay + az * az)
    return l > 1e-6 and (s.x * ax + s.y * ay + s.z * az) / l or 0
  end
  return along(r.left), along(r.back), along(r.up)
end

local function wrapNodeCollision()
  if _wrapped then return end
  _wrapped = true
  local orig = onNodeCollision
  onNodeCollision = function(id1, pos, normal, nodeVel, perpVel, slipVec, slipVel, slipForce, normalForce, depth, m1, m2)
    if orig then orig(id1, pos, normal, nodeVel, perpVel, slipVec, slipVel, slipForce, normalForce, depth, m1, m2) end
    if not enabled then return end
    if not normalForce or normalForce < FORCE_MIN then return end
    if not slipVel or slipVel < SLIP_MIN then return end
    if m1 == RUBBER_MAT or m2 == RUBBER_MAT then return end
    if wheelNodes and wheelNodes[id1] then return end
    local now = obj:getSimTime()
    if (nodeCooldown[id1] or 0) > now or now < nextHitT then return end
    nodeCooldown[id1] = now + COOLDOWN
    nextHitT = now + CAR_GAP
    pcall(function()
      local a, b, c = 0, 0, 0
      if slipVec then a, b, c = alongRefs(slipVec) end
      if DEBUG then print(('[carSurfaceFxScratch] hit node=%d force=%.0f slip=%.1f dir=(%.2f,%.2f,%.2f)'):format(id1, normalForce, slipVel, a, b, c)) end
      obj:queueGameEngineLua(('if carSurfaceFx_scratch then carSurfaceFx_scratch.hit(%d,%d,%.0f,%.2f,%.3f,%.3f,%.3f) end'):format(
        obj:getId(), id1, normalForce, slipVel, a, b, c))
    end)
  end
end

-- ---- config the GE side pushes to us ----
function M.setConfig(en) enabled = en and true or false end
function M.setDebug(v) DEBUG = v and true or false end   -- console: carSurfaceFxScratch.setDebug(true)

-- ---- lifecycle ----
function M.onExtensionLoaded() wheelNodes = nil; nodeCooldown = {}; wrapNodeCollision() end
function M.updateGFX(dt)
  pcall(function() if not wheelNodes then local s = buildWheelNodes(); if next(s) then wheelNodes = s end end end)
end
function M.onReset() nodeCooldown = {}; nextHitT = 0 end

return M
