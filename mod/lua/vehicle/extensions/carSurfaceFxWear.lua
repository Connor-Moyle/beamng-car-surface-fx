-- Car Surface FX, vehicle side: body wear. Listens to the car's contacts through carSurfaceFxContact (the one shared wrapper of onNodeCollision) and decides which of them wear the
-- body: a body node pressing hard enough against something while it slides along it. Each contact is sorted (a tyre, a wheel node, too light, not sliding, too soon after the last
-- one on that node, or a hit) and counted, so the game side can say why a scrape left nothing. A hit says where (the node), how hard (force, slip), and what it touched
-- (ground, wall, another vehicle, from the surface normal and the material). The numbers are the game's own contact data: perp and slip in m/s, force in N.
local M = {}

local FORCE_MIN = 600            -- N: lighter contacts are leaning, not scraping
local SLIP_MIN = 1.0             -- m/s along the surface
local COOLDOWN = 0.10            -- s between hits on one node
local CAR_GAP = 0.02             -- s between hits of the whole car: a big crash cannot flood the game side
local RUBBER_MAT = 4             -- the tyre's own material id
local NODE_MATS = { [2] = true, [3] = true, [5] = true }       -- metal, plastic, glass: what another car's body is made of

local enabled, debug = false, false
local cooldown, nextHit, nextReport, nextLog = {}, 0, 0, 0
local n = { seen = 0, tyre = 0, wheel = 0, light = 0, still = 0, cool = 0, hits = 0, maxForce = 0, maxSlip = 0, ground = 0, wall = 0, vehicle = 0, unknown = 0 }

-- ground, wall or a vehicle: from the surface normal (up = ground) and the material of what was touched. No normal in the event: 'unknown'.
function M.classify(nz, mat2)
  if nz == nil then return 'unknown' end
  if nz > 0.7 then return 'ground' end
  if NODE_MATS[mat2] then return 'vehicle' end
  return 'wall'
end

-- what a contact is: 'tyre', 'wheel', 'light', 'still' (these four are not hits), or nil when it is one. Pure, so it can be tested.
function M.reject(isWheel, mat1, mat2, force, slip)
  if mat1 == RUBBER_MAT or mat2 == RUBBER_MAT then return 'tyre' end
  if isWheel then return 'wheel' end
  if force < FORCE_MIN then return 'light' end
  if slip < SLIP_MIN then return 'still' end
  return nil
end

-- 0..1: how much wear a hit does, from the force and the sliding speed
function M.severity(force, slip) return math.min(1, force / 15000) * math.min(1, slip / 8) end

-- a world direction as components along the car's ref->left / ref->back / ref->up node lines (the game side knows the same three lines, so no axis convention is assumed)
local function alongRefs(x, y, z)
  local r = v.data.refNodes and v.data.refNodes[0]
  if not r then return 0, 0, 0 end
  local p0 = obj:getNodePosition(r.ref)
  local function along(id)
    local p = obj:getNodePosition(id)
    local ax, ay, az = p.x - p0.x, p.y - p0.y, p.z - p0.z
    local l = math.sqrt(ax * ax + ay * ay + az * az)
    return l > 1e-6 and (x * ax + y * ay + z * az) / l or 0
  end
  return along(r.left), along(r.back), along(r.up)
end

local function onContact(ev)
  if not enabled then return end
  if ev.kind ~= 'node' then return end
  n.seen = n.seen + 1
  local force, slip = ev.normalForce or 0, ev.slip or 0
  if force > n.maxForce then n.maxForce = force end
  if slip > n.maxSlip then n.maxSlip = slip end
  local why = M.reject(carSurfaceFxContact.isWheelNode(ev.node), ev.mat1, ev.mat2, force, slip)
  if why then n[why] = n[why] + 1 return end
  local now = obj:getSimTime()
  if (cooldown[ev.node] or 0) > now or now < nextHit then n.cool = n.cool + 1 return end
  cooldown[ev.node], nextHit = now + COOLDOWN, now + CAR_GAP
  local kind = M.classify(ev.nz, ev.mat2)
  n.hits, n[kind] = n.hits + 1, n[kind] + 1
  local a, b, c = 0, 0, 0
  if ev.slipDirX then a, b, c = alongRefs(ev.slipDirX, ev.slipDirY, ev.slipDirZ) end
  if debug and now >= nextLog then
    nextLog = now + 0.1
    log('I', 'carSurfaceFxWear', string.format('hit node=%d %s force=%.0f slip=%.1f speed=%.1f mat=%s/%s nz=%s dir=(%.2f,%.2f,%.2f)', ev.node, kind, force, slip, ev.speed or 0, tostring(ev.mat1), tostring(ev.mat2), tostring(ev.nz), a, b, c))
  end
  obj:queueGameEngineLua(string.format('if carSurfaceFx_bodywear then carSurfaceFx_bodywear.hit(%d,%d,"%s",%d,%.0f,%.2f,%.2f,%.3f,%.3f,%.3f) end', obj:getId(), ev.node, kind, ev.mat2 or 0, force, slip, ev.speed or 0, a, b, c))
end

-- once a second, when anything was seen: the counts of this interval, so the game side can say why a scrape left no mark
local function report(now)
  if now < nextReport then return end
  nextReport = now + 1
  if n.seen == 0 then return end
  obj:queueGameEngineLua(string.format('if carSurfaceFx_bodywear then carSurfaceFx_bodywear.report(%d,%d,%d,%d,%d,%d,%d,%d,%.0f,%.1f) end', obj:getId(), n.seen, n.hits, n.light, n.still, n.tyre, n.wheel, n.cool, n.maxForce, n.maxSlip))
  for k in pairs(n) do n[k] = 0 end
end

function M.setConfig(on, dbg)
  enabled, debug = on and true or false, dbg and true or false
  if enabled then
    carSurfaceFxContact.subscribe('bodywear', onContact)
    carSurfaceFxContact.setActive(true)
  else
    carSurfaceFxContact.unsubscribe('bodywear')
  end
end

function M.updateGFX()
  if not enabled then return end
  local ok = pcall(report, obj:getSimTime())
  if not ok then enabled = false end                       -- our code never gets to disable the vehicle: one error switches the wear of this car off
end
function M.onReset() cooldown, nextHit = {}, 0 end
function M.onExtensionUnloaded() enabled = false if carSurfaceFxContact then carSurfaceFxContact.unsubscribe('bodywear') end end

return M
