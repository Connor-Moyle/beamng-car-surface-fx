-- Car Surface FX: which way water runs on each window. The drops of a window live in the canvas of the glass material, in that material's UV space, and every pane has its own UV
-- layout (turned, mirrored), so "down the glass" cannot be one axis for the whole car. Here the car's own source mesh (.dae) says it: for every triangle of the glass the three
-- directions that move water, expressed in the pane's UV space, are put into a coarse grid over the canvas:
--   g = down (gravity), b = back (the airflow of driving, and a car that accelerates), r = right (what a corner pushes sideways), each as a direction in the UV plane times how
--   much of that direction lies along the pane (a flat sunroof has no slope, so water does not run on it).
-- The page (sim.js) reads the cell under a drop. The grid is 32 x 32 per material, sent to the page in pieces. Directions are in the car's jbeam frame: x left, y back, z up.
local M = {}

local N = 32                                  -- cells per side
local TAG = 'carSurfaceFx_glassflow'
local cache = {}                              -- key -> { [dae material name] = { g, b, r } }
local jobs = {}

local floor, sqrt = math.floor, math.sqrt

-- the flow of one triangle: pos = { x1,y1,z1, x2,.. , x3,.. }, uv = { u1,v1, u2,v2, u3,v3 }; returns for each of the three directions (down, back, right) { du, dv } or nil for a
-- degenerate triangle. du, dv is a UV direction (unit) multiplied by the slope: 1 when the direction lies in the pane, 0 when it is the pane's normal.
local DIRS = { { 0, 0, -1 }, { 0, 1, 0 }, { -1, 0, 0 } }
function M.triangleFlow(pos, uv)
  local e1x, e1y, e1z = pos[4] - pos[1], pos[5] - pos[2], pos[6] - pos[3]
  local e2x, e2y, e2z = pos[7] - pos[1], pos[8] - pos[2], pos[9] - pos[3]
  local du1, dv1, du2, dv2 = uv[3] - uv[1], uv[4] - uv[2], uv[5] - uv[1], uv[6] - uv[2]
  local g11, g12, g22 = e1x * e1x + e1y * e1y + e1z * e1z, e1x * e2x + e1y * e2y + e1z * e2z, e2x * e2x + e2y * e2y + e2z * e2z
  local det = g11 * g22 - g12 * g12
  if det < 1e-14 then return nil end
  -- the gradients of u and v along the pane (3D vectors): grad = A * du1 + B * du2
  local Ax, Ay, Az = (g22 * e1x - g12 * e2x) / det, (g22 * e1y - g12 * e2y) / det, (g22 * e1z - g12 * e2z) / det
  local Bx, By, Bz = (g11 * e2x - g12 * e1x) / det, (g11 * e2y - g12 * e1y) / det, (g11 * e2z - g12 * e1z) / det
  local gux, guy, guz = Ax * du1 + Bx * du2, Ay * du1 + By * du2, Az * du1 + Bz * du2
  local gvx, gvy, gvz = Ax * dv1 + Bx * dv2, Ay * dv1 + By * dv2, Az * dv1 + Bz * dv2
  -- the pane's normal, to know how much of a direction lies along the pane
  local nx, ny, nz = e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
  local nl = sqrt(nx * nx + ny * ny + nz * nz)
  nx, ny, nz = nx / nl, ny / nl, nz / nl
  local out = {}
  for i, d in ipairs(DIRS) do
    local k = d[1] * nx + d[2] * ny + d[3] * nz
    local px, py, pz = d[1] - k * nx, d[2] - k * ny, d[3] - k * nz                 -- the part of the direction in the pane
    local slope = sqrt(px * px + py * py + pz * pz)
    local u, v = gux * px + guy * py + guz * pz, gvx * px + gvy * py + gvz * pz
    local l = sqrt(u * u + v * v)
    out[i] = l > 1e-9 and { u / l * slope, v / l * slope } or { 0, 0 }
  end
  out.s = sqrt((gux * gux + guy * guy + guz * guz + gvx * gvx + gvy * gvy + gvz * gvz) / 2)           -- texture units per metre of this triangle
  return out
end

-- tris = list of { pos = {9 numbers}, uv = {6 numbers} } -> { g = { N*N*2 numbers }, b = ..., r = ..., filled = cells with data }
function M.field(tris)
  local flipped = {}                                                  -- the web canvas has its top row at v = 1 (the .dae's v runs up): a window sits in the rows the page draws in only when v is turned over (seen with the labelled debug grid)
  local cv = require('carSurfaceFx/daeread').canvasV
  for i, t in ipairs(tris) do local u = t.uv flipped[i] = { pos = t.pos, mesh = t.mesh, uv = { u[1], cv(u[2]), u[3], cv(u[4]), u[5], cv(u[6]) } } end
  tris = flipped
  local ymin, ymax = 1e9, -1e9                                        -- the rear glass: faces mostly along the car (not a side window) and lies in the back of the glass's length
  for _, t in ipairs(tris) do for i = 2, 8, 3 do ymin, ymax = math.min(ymin, t.pos[i]), math.max(ymax, t.pos[i]) end end
  local rearC = {}
  local sSum, sN = 0, 0
  local sum, cnt = { {}, {}, {} }, {}
  for i = 1, N * N do cnt[i] = 0 for d = 1, 3 do sum[d][i * 2 - 1], sum[d][i * 2] = 0, 0 end end
  for _, t in ipairs(tris) do
    local flow = M.triangleFlow(t.pos, t.uv)
    if flow then
      local uv = { t.uv[1], t.uv[2], t.uv[3], t.uv[4], t.uv[5], t.uv[6] }                -- texture coordinates outside 0..1 wrap around (the engine tiles the map): bring the triangle into the first tile
      local ou, ov = floor((uv[1] + uv[3] + uv[5]) / 3), floor((uv[2] + uv[4] + uv[6]) / 3)
      uv[1], uv[3], uv[5], uv[2], uv[4], uv[6] = uv[1] - ou, uv[3] - ou, uv[5] - ou, uv[2] - ov, uv[4] - ov, uv[6] - ov
      if flow.s > 1e-6 and flow.s < 50 then sSum, sN = sSum + flow.s, sN + 1 end
      local p = t.pos
      local e1x, e1y, e1z, e2x, e2y, e2z = p[4] - p[1], p[5] - p[2], p[6] - p[3], p[7] - p[1], p[8] - p[2], p[9] - p[3]
      local nx, ny, nz = e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
      local nl = sqrt(nx * nx + ny * ny + nz * nz)
      local isRear = nl > 1e-12 and math.abs(ny) / nl > 0.5 and (p[2] + p[5] + p[8]) / 3 > ymin + 0.6 * (ymax - ymin)
      local x0, x1 = math.min(uv[1], uv[3], uv[5]), math.max(uv[1], uv[3], uv[5])
      local y0, y1 = math.min(uv[2], uv[4], uv[6]), math.max(uv[2], uv[4], uv[6])
      local cx0, cx1 = floor(x0 * N), floor(x1 * N)
      local cy0, cy1 = floor(y0 * N), floor(y1 * N)
      local det = (uv[3] - uv[1]) * (uv[6] - uv[2]) - (uv[5] - uv[1]) * (uv[4] - uv[2])
      for cy = math.max(0, cy0), math.min(N - 1, cy1) do
        for cx = math.max(0, cx0), math.min(N - 1, cx1) do
          local px, py = (cx + 0.5) / N, (cy + 0.5) / N
          local inside = false
          if math.abs(det) > 1e-12 then
            local a = ((px - uv[1]) * (uv[6] - uv[2]) - (uv[5] - uv[1]) * (py - uv[2])) / det
            local b = ((uv[3] - uv[1]) * (py - uv[2]) - (px - uv[1]) * (uv[4] - uv[2])) / det
            inside = a >= 0 and b >= 0 and a + b <= 1
          end
          if inside or (cx0 == cx1 and cy0 == cy1) then               -- a triangle smaller than a cell still marks the cell it is in
            local c = cy * N + cx + 1
            cnt[c] = cnt[c] + 1
            if isRear then rearC[c] = true end
            for d = 1, 3 do sum[d][c * 2 - 1], sum[d][c * 2] = sum[d][c * 2 - 1] + flow[d][1], sum[d][c * 2] + flow[d][2] end
          end
        end
      end
    end
  end
  local out, filled = { g = {}, b = {}, r = {} }, 0
  local names = { 'g', 'b', 'r' }
  for c = 1, N * N do
    for d = 1, 3 do
      local k = cnt[c] > 0 and 1 / cnt[c] or 0
      out[names[d]][c * 2 - 1], out[names[d]][c * 2] = sum[d][c * 2 - 1] * k, sum[d][c * 2] * k
    end
    if cnt[c] > 0 then filled = filled + 1 end
  end
  -- a cell with nothing in it (the gap between two triangles) takes its neighbours' mean, twice
  for _ = 1, 2 do
    local fill = {}
    for c = 1, N * N do fill[c] = cnt[c] end
    for cy = 0, N - 1 do for cx = 0, N - 1 do
      local c = cy * N + cx + 1
      if cnt[c] == 0 then
        local n, acc = 0, { { 0, 0 }, { 0, 0 }, { 0, 0 } }
        for dy = -1, 1 do for dx = -1, 1 do
          local ax, ay = cx + dx, cy + dy
          if ax >= 0 and ay >= 0 and ax < N and ay < N then
            local k = ay * N + ax + 1
            if cnt[k] > 0 then
              n = n + 1
              for d = 1, 3 do acc[d][1], acc[d][2] = acc[d][1] + out[names[d]][k * 2 - 1], acc[d][2] + out[names[d]][k * 2] end
            end
          end
        end end
        if n > 0 then
          for d = 1, 3 do out[names[d]][c * 2 - 1], out[names[d]][c * 2] = acc[d][1] / n, acc[d][2] / n end
          fill[c] = 1
        end
      end
    end end
    cnt = fill
  end
  out.filled = filled
  out.m = {}
  for c = 1, N * N do out.m[c] = cnt[c] > 0 and (rearC[c] and 2 or 1) or 0 end        -- the cells that are glass (1) and the rear glass (2): drops are only made there
  out.uvPerM = sN > 0 and sSum / sN or 0.5                                       -- the mean of the pane triangles: a drop of a given size in millimetres is this many texture units per metre
  return out
end

local read = require('carSurfaceFx/daeread').read

-- the field of every glass material of a car, built a few ms a frame: cb({ [dae material name] = field }) or cb(nil). glassMat = { [dae material name] = true }
function M.request(vehId, glassMat, cb)
  local vd = core_vehicle_manager.getVehicleData(vehId)
  if not (vd and vd.vdata) then return cb(nil) end
  local wanted, names = {}, {}
  for _, f in pairs(vd.vdata.flexbodies or {}) do if f.mesh then wanted[f.mesh] = f names[#names + 1] = f.mesh end end
  table.sort(names)
  local mats = {}
  for k in pairs(glassMat) do mats[#mats + 1] = k end
  table.sort(mats)
  local key = tostring(vd.vehicleDirectory) .. '|' .. table.concat(mats, ',') .. '|' .. table.concat(names, ',')
  if cache[key] then return cb(cache[key]) end
  local co = coroutine.create(function()
    local tris, stats = {}, { daeMats = {}, nodes = {}, nodeCount = 0 }
    local files = {}
    pcall(function() files = FS:findFiles(vd.vehicleDirectory, '*.dae', -1, false, false) or {} end)
    for _, path in ipairs(files) do
      local ok, err = pcall(read, path, wanted, glassMat, nil, tris, stats)
      if not ok then log('W', TAG, 'could not read ' .. path .. ': ' .. tostring(err)) end
      coroutine.yield()
    end
    local byMat = {}
    for _, t in ipairs(tris) do byMat[t.mat] = byMat[t.mat] or {} table.insert(byMat[t.mat], t) end
    local out = {}
    for mn, list in pairs(byMat) do out[mn] = M.field(list) end
    cache[key] = out
    local info = { tris = #tris, files = #files, nodeCount = stats.nodeCount, matched = 0, wantedMats = table.concat(mats, ','), fields = {} }
    for _ in pairs(stats.nodes) do info.matched = info.matched + 1 end
    for mn, f in pairs(out) do info.fields[#info.fields + 1] = string.format('%s: %d cells, %.2f/m', mn, f.filled, f.uvPerM) end
    out._info = info
    local per, names = {}, {}
    for _, t in ipairs(tris) do                                       -- which fitted meshes gave the pane cells, and where they lie on the texture
      local m = per[t.mesh]
      if not m then m = { n = 0, u0 = 9, u1 = -9, v0 = 9, v1 = -9 } per[t.mesh] = m names[#names + 1] = t.mesh end
      m.n = m.n + 1
      for i = 0, 2 do
        local u, v = t.uv[i * 2 + 1], t.uv[i * 2 + 2]
        if u < m.u0 then m.u0 = u end if u > m.u1 then m.u1 = u end if v < m.v0 then m.v0 = v end if v > m.v1 then m.v1 = v end
      end
    end
    table.sort(names)
    local ml = {}
    for _, nm in ipairs(names) do local m = per[nm] ml[#ml + 1] = string.format('%s:%d u%.2f-%.2f v%.2f-%.2f', nm, m.n, m.u0, m.u1, m.v0, m.v1) end
    info.meshes = table.concat(ml, '; ')
    local line = string.format('%s: %d glass triangles, %d .dae file(s), %d fitted meshes found of %d nodes; materials asked for [%s]; cells [%s]; meshes [%s]', tostring(vd.vehicleDirectory), #tris, #files, info.matched, stats.nodeCount, info.wantedMats, table.concat(info.fields, '; '), info.meshes)
    if #tris == 0 then
      local glassy = {}
      for nm in pairs(stats.daeMats) do if nm:lower():find('glass', 1, true) then glassy[#glassy + 1] = nm end end
      table.sort(glassy)
      log('W', TAG, line .. ' - NOTHING FOUND. glass-like materials in the .dae: [' .. table.concat(glassy, ', ') .. ']')
    else
      log('I', TAG, line)
    end
    return out
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

-- one field as the lines the page takes: csfxFlow(kind, firstIndex, { integers }) in pieces of 256 numbers, directions times 100 as whole numbers
function M.messages(field)
  local out = {}
  for _, kind in ipairs({ 'g', 'b', 'r', 'm' }) do
    local list = field[kind]
    for start = 1, #list, 256 do
      local part = {}
      for i = start, math.min(#list, start + 255) do part[#part + 1] = floor(list[i] * 100 + (list[i] >= 0 and 0.5 or -0.5)) end
      out[#out + 1] = string.format('csfxFlow("%s",%d,[%s])', kind, start - 1, table.concat(part, ','))
    end
  end
  return out
end

M.N = N
return M
