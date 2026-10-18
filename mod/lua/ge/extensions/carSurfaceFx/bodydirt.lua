-- Car Surface FX: builds a car's body map (carSurfaceFx/bodymap.lua) from its own mesh, a few milliseconds a frame, once per car model and cached. The paint is on the second texture
-- coordinate set of the mesh (the one the paint canvas is drawn in).
local M = {}

local TAG = 'carSurfaceFx_bodydirt'
local read = require('carSurfaceFx/daeread').read
local bodymap = require('carSurfaceFx/bodymap')
local spraytrace = require('carSurfaceFx/spraytrace')
local cache, jobs = {}, {}

-- the wheels' centres and radii in the car's frame: { { x, y, z, r }, ... } from the vehicle data (nodes at rest)
function M.wheelList(vdata)
  local pos = {}
  for _, n in pairs(vdata.nodes or {}) do pos[n.cid] = n.pos end
  local out = {}
  for _, wd in pairs(vdata.wheels or {}) do
    local a, b = pos[wd.node1], pos[wd.node2]
    if a and b then out[#out + 1] = { x = (a.x + b.x) / 2, y = (a.y + b.y) / 2, z = (a.z + b.z) / 2, r = wd.radius or 0.34 } end
  end
  table.sort(out, function(p, q) if p.y ~= q.y then return p.y < q.y end return p.x < q.x end)          -- front left, front right, rear left, rear right
  return out
end

-- cb(map) later (nil when the car has no usable source mesh). paintMat = { [dae material name] = true }
function M.request(vehId, paintMat, cb)
  local vd = core_vehicle_manager.getVehicleData(vehId)
  if not (vd and vd.vdata) then return cb(nil) end
  local wanted, names = {}, {}
  for _, f in pairs(vd.vdata.flexbodies or {}) do if f.mesh then wanted[f.mesh] = f names[#names + 1] = f.mesh end end
  table.sort(names)
  local mats = {}
  for k in pairs(paintMat) do mats[#mats + 1] = k end
  table.sort(mats)
  local key = tostring(vd.vehicleDirectory) .. '|' .. table.concat(mats, ',') .. '|' .. table.concat(names, ',')
  if cache[key] then return cb(cache[key]) end
  local co = coroutine.create(function()
    local tris, files = {}, {}
    pcall(function() files = FS:findFiles(vd.vehicleDirectory, '*.dae', -1, false, false) or {} end)
    for _, path in ipairs(files) do
      local ok, err = pcall(read, path, wanted, paintMat, 1, tris)
      if not ok then log('W', TAG, 'could not read ' .. path .. ': ' .. tostring(err)) end
      coroutine.yield()
    end
    local wheels = M.wheelList(vd.vdata)
    local map = bodymap.build(tris, wheels)
    if map then
      if #wheels > 0 then map.spray = spraytrace.bake(tris, wheels, { speed = 20, rays = 500, yield = coroutine.yield }) end        -- where the mud thrown by each tyre really lands (rays from the tread, traced against the body)
      cache[key] = map
      log('I', TAG, string.format('%s: body map from %d paint triangles, %d texture cells, %d wheels', tostring(vd.vehicleDirectory), #tris, #map.list, #map.wheels))
    else
      log('I', TAG, tostring(vd.vehicleDirectory) .. ': no paint triangles found, the dirt uses the plain placement')
    end
    return map
  end)
  jobs[#jobs + 1] = { co = co, cb = cb }
end

function M.tick()
  local job = jobs[1]
  if not job then return end
  local t0 = os.clock()
  repeat
    local ok, res = coroutine.resume(job.co)
    if coroutine.status(job.co) == 'dead' then
      table.remove(jobs, 1)
      if not ok then log('E', TAG, 'build failed: ' .. tostring(res)) res = nil end
      job.cb(res)
      return
    end
  until (os.clock() - t0) * 1000 > 6
end

return M
