-- Car Surface FX: where the windscreen is on the screen, for the rain overlay of the driver's view (the game's own web UI layer draws the drops, see
-- ui/modModules/csfxRain). The windscreen is the flexbody whose mesh name says windshield/windscreen (not its inside pane or the broken twin); its nodes are projected
-- through the camera and the convex hull of the points is the area the drops are clipped to. Plain functions where possible so they are tested outside the game.
local M = {}

-- the convex hull of points { x, y } (monotone chain), counter-clockwise as seen with y up; fewer than 3 points: nil
function M.convexHull(pts)
  if #pts < 3 then return nil end
  local p = {}
  for i, q in ipairs(pts) do p[i] = q end
  table.sort(p, function(a, b) return a.x < b.x or (a.x == b.x and a.y < b.y) end)
  local function cross(o, a, b) return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) end
  local h = {}
  for i = 1, #p do
    while #h >= 2 and cross(h[#h - 1], h[#h], p[i]) <= 0 do h[#h] = nil end
    h[#h + 1] = p[i]
  end
  local lower = #h + 1
  for i = #p - 1, 1, -1 do
    while #h >= lower and cross(h[#h - 1], h[#h], p[i]) <= 0 do h[#h] = nil end
    h[#h + 1] = p[i]
  end
  h[#h] = nil
  return #h >= 3 and h or nil
end

-- world point -> screen fractions (0..1, y down) through a camera { x, y, z (position), r, f, u = {x,y,z} unit vectors right/forward/up, halfTan, aspect }; nil behind the camera
function M.project(p, cam)
  local dx, dy, dz = p.x - cam.x, p.y - cam.y, p.z - cam.z
  local depth = dx * cam.f.x + dy * cam.f.y + dz * cam.f.z
  if depth <= 0.01 then return nil end
  local nx = (dx * cam.r.x + dy * cam.r.y + dz * cam.r.z) / (depth * cam.halfTan * cam.aspect)
  local ny = (dx * cam.u.x + dy * cam.u.y + dz * cam.u.z) / (depth * cam.halfTan)
  return { x = (nx + 1) * 0.5, y = (1 - ny) * 0.5 }
end

-- the hull as a flat list { x1, y1, x2, y2, ... } for the page, 4 decimals, or nil
function M.flat(hull)
  if not hull then return nil end
  local out = {}
  for _, q in ipairs(hull) do out[#out + 1] = math.floor(q.x * 10000 + 0.5) / 10000 out[#out + 1] = math.floor(q.y * 10000 + 0.5) / 10000 end
  return out
end

-- is this flexbody mesh a windscreen (the outer pane)?
function M.isWindscreenMesh(name)
  local n = tostring(name):lower()
  if not (n:find('windshield', 1, true) or n:find('windscreen', 1, true)) then return false end
  return not (n:find('_int', 1, true) or n:find('dmg', 1, true) or n:find('broken', 1, true) or n:find('crack', 1, true))
end

-- Rotating a vector by a unit quaternion { x, y, z, w }.
function M.qrot(q, v)
  local tx, ty, tz = 2 * (q.y * v.z - q.z * v.y), 2 * (q.z * v.x - q.x * v.z), 2 * (q.x * v.y - q.y * v.x)
  return { x = v.x + q.w * tx + (q.y * tz - q.z * ty), y = v.y + q.w * ty + (q.z * tx - q.x * tz), z = v.z + q.w * tz + (q.x * ty - q.y * tx) }
end

-- The camera's position as read from the camera is a frame behind the car's, which is invisible at rest and puts the windscreen many centimetres off at speed (the car moves
-- 0.3 m in a frame at 20 m/s, the windscreen is about one metre from the eye). In the driver's view the eye sits still in the car's own frame, so: while the car is nearly
-- still the eye's offset in the car's frame is learned, and at speed the camera position is rebuilt from the car's position and rotation of THIS frame and that offset.
-- state = { off = { x, y, z } or nil } per car; cam = { x, y, z, ... } is changed in place; returns the correction in metres.
function M.stabilise(state, cam, vpos, vq, speed)
  local inv = { x = -vq.x, y = -vq.y, z = -vq.z, w = vq.w }
  if speed < 1 or not state.off then state.off = M.qrot(inv, { x = cam.x - vpos.x, y = cam.y - vpos.y, z = cam.z - vpos.z }) end
  local w = M.qrot(vq, state.off)
  local nx, ny, nz = vpos.x + w.x, vpos.y + w.y, vpos.z + w.z
  local d = math.sqrt((nx - cam.x) ^ 2 + (ny - cam.y) ^ 2 + (nz - cam.z) ^ 2)
  cam.x, cam.y, cam.z = nx, ny, nz
  return d
end

-- ---- the game side ----
local nodesBy = {}
local eyeBy = {}                                    -- vehicle id -> the eye's offset in the car's frame (see stabilise)
M.last = {}                                          -- what the last projection saw, for the diagnostics                                    -- vehicle id -> { cid, ... } (the windscreen's nodes), false when the car has none

local function windscreenNodes(id)
  if nodesBy[id] ~= nil then return nodesBy[id] end
  local data = core_vehicle_manager and core_vehicle_manager.getVehicleData(id)
  local list = {}
  for _, fb in pairs(data and data.vdata and data.vdata.flexbodies or {}) do
    if fb.mesh and M.isWindscreenMesh(fb.mesh) then
      for _, cid in ipairs(fb['_group_nodes'] or {}) do list[#list + 1] = cid end
    end
  end
  nodesBy[id] = #list >= 3 and list or false
  return nodesBy[id]
end

function M.forget(id) nodesBy[id] = nil eyeBy[id] = nil end
function M.resetEye(id) eyeBy[id] = nil end

-- the camera as M.project wants it (a test can replace this function)
function M.camera()
  if not (core_camera and core_camera.getPosition and core_camera.getQuat and core_camera.getFovRad) then return nil end
  local pos, q, fov = core_camera.getPosition(), core_camera.getQuat(), core_camera.getFovRad()
  local canvas = scenetree.findObject('Canvas')
  if not (pos and q and fov and fov > 0 and canvas and canvas.getWindowClientSizeXY) then return nil end
  local w, h = canvas:getWindowClientSizeXY()
  if not (w and h and w > 0 and h > 0) then return nil end
  local r, f, u = q * vec3(1, 0, 0), q * vec3(0, 1, 0), q * vec3(0, 0, 1)
  return { x = pos.x, y = pos.y, z = pos.z, r = { x = r.x, y = r.y, z = r.z }, f = { x = f.x, y = f.y, z = f.z }, u = { x = u.x, y = u.y, z = u.z },
    halfTan = math.tan(fov * 0.5), aspect = w / h }
end

-- the windscreen of car veh on the screen as a flat hull list, or nil (no windscreen found, behind the camera, off the screen)
function M.windscreen(veh)
  local nodes = windscreenNodes(veh:getID())
  local cam = M.camera()
  if not (nodes and cam) then return nil end
  local base = veh:getPosition()
  local last = M.last
  last.speed, last.fix = 0, 0
  local okQ, vq = pcall(function() return veh:getRotation() end)
  if okQ and vq and vq.w then
    local v = veh:getVelocity()
    local speed = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    eyeBy[veh:getID()] = eyeBy[veh:getID()] or {}
    last.speed, last.fix = speed, M.stabilise(eyeBy[veh:getID()], cam, base, vq, speed)
  end
  local pts = {}
  for _, cid in ipairs(nodes) do
    local w = veh:getNodePosition(cid)
    local s = M.project({ x = w.x + base.x, y = w.y + base.y, z = w.z + base.z }, cam)
    if s then pts[#pts + 1] = s end
  end
  local hull = M.flat(M.convexHull(pts))
  if hull then
    local x0, y0, x1, y1 = 1, 1, 0, 0
    for i = 1, #hull, 2 do x0, x1, y0, y1 = math.min(x0, hull[i]), math.max(x1, hull[i]), math.min(y0, hull[i + 1]), math.max(y1, hull[i + 1]) end
    last.box = string.format('%.2f,%.2f..%.2f,%.2f', x0, y0, x1, y1)
  else
    last.box = 'none'
  end
  last.points = #pts
  return hull
end

return M
