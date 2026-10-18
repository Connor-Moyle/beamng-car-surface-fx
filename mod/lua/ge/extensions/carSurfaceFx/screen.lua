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

-- A convex polygon { {x, y}, ... } clipped to the rectangle x0..x1, y0..y1 (Sutherland-Hodgman, one side at a time): the part of the windscreen that is on the screen.
-- nil when fewer than 3 points are left (nothing of it is on the screen). The windscreen is close to the eye, so its outline runs off the screen; unclipped, the page would
-- lay its drops over an area several times the screen and size them by it.
function M.clipHull(poly, x0, y0, x1, y1)
  if not poly then return nil end
  local function side(list, axis, bound, keepAbove)
    local out = {}
    local n = #list
    for i = 1, n do
      local a, b = list[i], list[i % n + 1]
      local av, bv = a[axis], b[axis]
      local ain = keepAbove and av >= bound or (not keepAbove and av <= bound)
      local bin = keepAbove and bv >= bound or (not keepAbove and bv <= bound)
      if ain then out[#out + 1] = a end
      if ain ~= bin then
        local t = (bound - av) / (bv - av)
        local p = { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t }
        p[axis] = bound
        out[#out + 1] = p
      end
    end
    return out
  end
  local list = poly
  list = side(list, 'x', x0, true)
  if #list < 3 then return nil end
  list = side(list, 'x', x1, false)
  if #list < 3 then return nil end
  list = side(list, 'y', y0, true)
  if #list < 3 then return nil end
  list = side(list, 'y', y1, false)
  if #list < 3 then return nil end
  local area = 0                                                    -- (a sliver along an edge, a polygon that only touches it: nothing to draw in)
  for i = 1, #list do local a, b = list[i], list[i % #list + 1] area = area + (a.x * b.y - b.x * a.y) end
  return math.abs(area) * 0.5 > 1e-5 and list or nil
end

-- the hull as a flat list { x1, y1, x2, y2, ... } for the page, 4 decimals, or nil
function M.flat(hull)
  if not hull then return nil end
  local out = {}
  for _, q in ipairs(hull) do out[#out + 1] = math.floor(q.x * 10000 + 0.5) / 10000 out[#out + 1] = math.floor(q.y * 10000 + 0.5) / 10000 end
  return out
end

-- the glass mesh runs up under the headliner and the pillar trim, so the part you can see is smaller than the node hull: shrink the hull toward its bottom centre
-- (kx across, ky up). On the covet the visible glass is about 0.93 as wide and 0.68 as tall as the hull; shortcut: one factor for every car, measure per car if one is off.
M.INSET = { 0.93, 0.68, 0.03, 0.012, 0.012 }
function M.inset(hull, kx, ky, lift, taper, rightTrim)
  if not hull then return nil end
  local x0, x1, ymin, ymax = 1, 0, 1, 0
  for i = 1, #hull, 2 do x0, x1, ymin, ymax = math.min(x0, hull[i]), math.max(x1, hull[i]), math.min(ymin, hull[i + 1]), math.max(ymax, hull[i + 1]) end
  local cx, out, h = (x0 + x1) / 2, {}, math.max(1e-6, ymax - ymin)
  lift = lift or 0
  local k2 = ky - lift / h                                          -- the bottom edge comes up by `lift` (the glass ends at the dash) and the top stays where ky put it
  for i = 1, #hull, 2 do
    local up = (ymax - hull[i + 1]) / h                              -- 0 at the bottom, 1 at the top
    local x = cx + (hull[i] - cx) * kx
    out[i] = x + (hull[i] < cx and 1 or -1) * (taper or 0) * up      -- the pillars lean in: the top is narrower than the bottom
    if hull[i] >= cx then out[i] = out[i] - (rightTrim or 0) end                      -- the right edge comes in a little more: drops showed on the right A-pillar (covet)
    out[i + 1] = ymax - lift - (ymax - hull[i + 1]) * k2
  end
  return out
end



-- is this flexbody mesh a windscreen (the outer pane)?
function M.isWindscreenMesh(name)
  local n = tostring(name):lower()
  if not (n:find('windshield', 1, true) or n:find('windscreen', 1, true)) then return false end
  return not (n:find('_int', 1, true) or n:find('dmg', 1, true) or n:find('broken', 1, true) or n:find('crack', 1, true))
end

-- A frame made from three of the car's own nodes (the reference, left, back and up nodes of its jbeam): the same data as the windscreen's nodes and the same moment, so no
-- rotation convention of the game can be wrong in it. fr = { o = {x,y,z}, ex, ey, ez = unit vectors }.
local function sub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function unit(a) local l = math.sqrt(dot(a, a)) if l < 1e-9 then return { x = 0, y = 0, z = 0 } end return { x = a.x / l, y = a.y / l, z = a.z / l } end
local function axpy(v, k, a) return { x = v.x - a.x * k, y = v.y - a.y * k, z = v.z - a.z * k } end
function M.makeFrame(pRef, pLeft, pBack, pUp)
  local ex = unit(sub(pLeft, pRef))
  local ey = unit(axpy(sub(pBack, pRef), dot(sub(pBack, pRef), ex), ex))
  local u = sub(pUp, pRef)
  local ez = unit(axpy(axpy(u, dot(u, ex), ex), dot(u, ey), ey))
  return { o = pRef, ex = ex, ey = ey, ez = ez }
end
function M.toFrame(fr, p) local d = sub(p, fr.o) return { x = dot(d, fr.ex), y = dot(d, fr.ey), z = dot(d, fr.ez) } end
function M.fromFrame(fr, l)
  return { x = fr.o.x + fr.ex.x * l.x + fr.ey.x * l.y + fr.ez.x * l.z, y = fr.o.y + fr.ex.y * l.x + fr.ey.y * l.y + fr.ez.y * l.z, z = fr.o.z + fr.ex.z * l.x + fr.ey.z * l.y + fr.ez.z * l.z }
end

-- The camera's position as read from the camera is a frame behind the car's, which is invisible at rest and puts the windscreen many centimetres off at speed (the car moves
-- 0.3 m in a frame at 20 m/s, the windscreen is about one metre from the eye). In the driver's view the eye sits still in the car's own frame, so: while the car is nearly
-- still the eye's offset in the car's frame is learned, and at speed the camera position is rebuilt from the car's frame of THIS frame and that offset.
-- state = { off = { x, y, z } or nil } per car; cam = { x, y, z, ... } is changed in place; returns the correction in metres.
-- When the car was never seen standing (an AI start, a spawn while rolling) the offset is first taken from a camera pushed forward by one frame of travel (vel, the car's velocity,
-- times M.LAG seconds), which is the lag it is assumed to have; it is learned exactly the first time the car is nearly still.
M.LAG = 1 / 60
function M.stabilise(state, cam, fr, speed, vel)
  if speed < 1 then
    state.off = M.toFrame(fr, cam)
  elseif not state.off then
    local l = vel and M.LAG or 0
    state.off = M.toFrame(fr, { x = cam.x + (vel and vel.x or 0) * l, y = cam.y + (vel and vel.y or 0) * l, z = cam.z + (vel and vel.z or 0) * l })
  end
  local n = M.fromFrame(fr, state.off)
  local d = math.sqrt((n.x - cam.x) ^ 2 + (n.y - cam.y) ^ 2 + (n.z - cam.z) ^ 2)
  cam.x, cam.y, cam.z = n.x, n.y, n.z
  return d
end

-- The windscreen's nodes also hold the pillars, the roof edge and the cowl they are attached to, which made the outline far bigger than the glass. The glass is a plane: fit
-- z = a x + b y + c through the nodes (in the car's frame) and drop the ones that sit far off it, a few rounds. pts = list of { x, y, z }; returns the indices of the nodes kept.
function M.planeInliers(pts)
  local keep = {}
  for i = 1, #pts do keep[i] = true end
  for _ = 1, 4 do
    local n, sx, sy, sz, sxx, sxy, syy, sxz, syz = 0, 0, 0, 0, 0, 0, 0, 0, 0
    for i, p in ipairs(pts) do
      if keep[i] then
        n, sx, sy, sz = n + 1, sx + p.x, sy + p.y, sz + p.z
        sxx, sxy, syy, sxz, syz = sxx + p.x * p.x, sxy + p.x * p.y, syy + p.y * p.y, sxz + p.x * p.z, syz + p.y * p.z
      end
    end
    if n < 4 then break end
    -- the normal equations of the least squares plane, solved by Cramer's rule
    local function det3(a, b, c, d, e, f, g, h, i) return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g) end
    local D = det3(sxx, sxy, sx, sxy, syy, sy, sx, sy, n)
    if math.abs(D) < 1e-9 then break end
    local a = det3(sxz, sxy, sx, syz, syy, sy, sz, sy, n) / D
    local b = det3(sxx, sxz, sx, sxy, syz, sy, sx, sz, n) / D
    local c = det3(sxx, sxy, sxz, sxy, syy, syz, sx, sy, sz) / D
    local ss, cnt = 0, 0
    local res = {}
    for i, p in ipairs(pts) do
      res[i] = math.abs(p.z - (a * p.x + b * p.y + c))
      if keep[i] then ss, cnt = ss + res[i] * res[i], cnt + 1 end
    end
    local limit = math.max(0.03, 2.0 * math.sqrt(ss / cnt))
    local changed, left = false, 0
    for i = 1, #pts do
      local k = res[i] <= limit
      if k ~= keep[i] then changed = true end
      keep[i] = k
      if k then left = left + 1 end
    end
    if not changed or left < 4 then break end
  end
  local out = {}
  for i = 1, #pts do if keep[i] then out[#out + 1] = i end end
  if #out < 4 then out = {} for i = 1, #pts do out[i] = i end end
  return out
end

-- ---- the game side ----
local frameIds = {}                                   -- vehicle id -> { ref, left, back, up } node ids of its jbeam, false when it has none
local glassBy = {}                                    -- vehicle id -> the windscreen nodes that lie on the glass (the plane fit), found once
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

function M.forget(id) nodesBy[id] = nil eyeBy[id] = nil frameIds[id] = nil glassBy[id] = nil end
function M.resetEye(id) eyeBy[id] = nil end

-- how many nodes the car's windscreen has (0: none found), for the screen trace
function M.windscreenNodeCount(id)
  local n = windscreenNodes(id)
  return n and #n or 0
end

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
local function frameOf(veh)
  local id = veh:getID()
  if frameIds[id] == nil then
    local data = core_vehicle_manager and core_vehicle_manager.getVehicleData(id)
    local r = data and data.vdata and data.vdata.refNodes and data.vdata.refNodes[0]
    frameIds[id] = (r and r.ref and r.left and r.back and r.up) and r or false
  end
  local r = frameIds[id]
  if not r then return nil end
  local base = veh:getPosition()
  local function P(cid) local w = veh:getNodePosition(cid) return { x = w.x + base.x, y = w.y + base.y, z = w.z + base.z } end
  return M.makeFrame(P(r.ref), P(r.left), P(r.back), P(r.up))
end

-- The nodes of a car's windscreen flexbody are not always the glass: the covet's lists 138 nodes over the whole car (nose to tailgate, a plane fit picks the hood and dash).
-- In the driver's view the glass is the part of them in front of the eye: a little way ahead (not the roof or the pillars beside the head, not the far hood) and not far
-- below or above the line of sight. list = { { r, u, d } ... } each node in the camera's frame (right, up, depth in m). Returns the indices, or nil when fewer than 4 qualify.
M.EYE_DEPTH, M.EYE_UP = { 0.15, 1.15 }, { -0.5, 0.7 }
function M.eyeNodes(list)
  local keep = {}
  for i, n in ipairs(list) do
    if n.d >= M.EYE_DEPTH[1] and n.d <= M.EYE_DEPTH[2] and n.u >= M.EYE_UP[1] and n.u <= M.EYE_UP[2] and math.abs(n.r) <= 1.0 then keep[#keep + 1] = i end
  end
  return #keep >= 4 and keep or nil
end

-- carSurfaceFx.windscreenDump(): for each flexbody the screen takes for the windscreen, its name and the node positions in the car's own frame (x left, y back, z up, from the
-- reference nodes), so the glass can be told from the rest of its node group offline. Returns a table.
function M.dump(veh)
  local id = veh:getID()
  local data = core_vehicle_manager and core_vehicle_manager.getVehicleData(id)
  local fr = frameOf(veh)
  local base = veh:getPosition()
  local out = { frame = fr and 'yes' or 'no', flexbodies = {} }
  for _, fb in pairs(data and data.vdata and data.vdata.flexbodies or {}) do
    if fb.mesh and M.isWindscreenMesh(fb.mesh) then
      local list = {}
      for _, cid in ipairs(fb['_group_nodes'] or {}) do
        local w = veh:getNodePosition(cid)
        local p = { x = w.x + base.x, y = w.y + base.y, z = w.z + base.z }
        local l = fr and M.toFrame(fr, p) or p
        list[#list + 1] = string.format('%d %.3f %.3f %.3f', cid, l.x, l.y, l.z)
      end
      out.flexbodies[#out.flexbodies + 1] = { mesh = fb.mesh, group = fb.group, nodes = list }
    end
  end
  return out
end

function M.windscreen(veh)
  local nodes = windscreenNodes(veh:getID())
  local cam = M.camera()
  if not (nodes and cam) then return nil end
  local base = veh:getPosition()
  local last = M.last
  last.speed, last.fix = 0, 0
  local fr = frameOf(veh)
  if fr then
    local id = veh:getID()
    if not glassBy[id] then                                          -- the nodes on the glass plane, once (the car's own frame, so it does not depend on how the car stands)
      local pts = {}
      for i, cid in ipairs(nodes) do
        local w = veh:getNodePosition(cid)
        pts[i] = M.toFrame(fr, { x = w.x + base.x, y = w.y + base.y, z = w.z + base.z })
      end
      local keep, list = M.planeInliers(pts), {}
      for _, i in ipairs(keep) do list[#list + 1] = nodes[i] end
      glassBy[id] = list
    end
    nodes = glassBy[id]
    local raw = windscreenNodes(id)
    if #raw > #nodes then                                             -- a flexbody for more than the windscreen: the part of it in front of the eye
      local cl = {}
      for i, cid in ipairs(raw) do
        local w = veh:getNodePosition(cid)
        local dx, dy, dz = w.x + base.x - cam.x, w.y + base.y - cam.y, w.z + base.z - cam.z
        cl[i] = { r = dx * cam.r.x + dy * cam.r.y + dz * cam.r.z, u = dx * cam.u.x + dy * cam.u.y + dz * cam.u.z, d = dx * cam.f.x + dy * cam.f.y + dz * cam.f.z }
      end
      local ix = M.eyeNodes(cl)
      if ix then nodes = {} for _, i in ipairs(ix) do nodes[#nodes + 1] = raw[i] end end
    end
    local v = veh:getVelocity()
    local speed = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    eyeBy[id] = eyeBy[id] or {}
    last.speed, last.fix = speed, M.stabilise(eyeBy[id], cam, fr, speed, v)
  end
  local pts = {}
  local sr, su, sd, sn = 0, 0, 0, 0               -- the nodes' mean place in the camera's own frame (right, up, depth in m), for the diagnostics
  for _, cid in ipairs(nodes) do
    local w = veh:getNodePosition(cid)
    local p = { x = w.x + base.x, y = w.y + base.y, z = w.z + base.z }
    local dx, dy, dz = p.x - cam.x, p.y - cam.y, p.z - cam.z
    sr, su, sd, sn = sr + dx * cam.r.x + dy * cam.r.y + dz * cam.r.z, su + dx * cam.u.x + dy * cam.u.y + dz * cam.u.z, sd + dx * cam.f.x + dy * cam.f.y + dz * cam.f.z, sn + 1
    local s = M.project(p, cam)
    if s then pts[#pts + 1] = s end
  end
  last.camera = sn > 0 and string.format('nodes %d mean in camera frame right %.2f up %.2f depth %.2f m | fov %.1f deg aspect %.2f | camera forward %.2f,%.2f,%.2f up %.2f,%.2f,%.2f', sn, sr / sn, su / sn, sd / sn, math.deg(2 * math.atan(cam.halfTan)), cam.aspect, cam.f.x, cam.f.y, cam.f.z, cam.u.x, cam.u.y, cam.u.z) or 'no nodes'
  local whole = M.convexHull(pts)
  local clipped = M.clipHull(whole, 0, 0, 1, 1)
  if clipped then                                                    -- a glass corner past the screen edge: the clip leaves a slanted bottom edge there, but the glass ends at the dash, level
    local mx, my = 0, 0
    for _, q in ipairs(clipped) do if q.x > mx then mx = q.x end if q.y > my then my = q.y end end
    if mx > 0.97 then clipped[#clipped + 1] = { x = mx, y = my } clipped = M.convexHull(clipped) or clipped end
  end
  local hull = M.inset(M.flat(clipped), M.INSET[1], M.INSET[2], M.INSET[3], M.INSET[4], M.INSET[5])
  last.clipped = whole ~= nil and hull ~= nil and #hull ~= #whole * 2
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
