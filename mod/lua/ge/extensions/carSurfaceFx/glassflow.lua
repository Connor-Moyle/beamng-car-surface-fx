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

local function nums(s)
  local t, n = {}, 0
  for tok in s:gmatch('[^%s]+') do n = n + 1 t[n] = tonumber(tok) end
  return t
end

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
  return out
end

-- tris = list of { pos = {9 numbers}, uv = {6 numbers} } -> { g = { N*N*2 numbers }, b = ..., r = ..., filled = cells with data }
function M.field(tris)
  local sum, cnt = { {}, {}, {} }, {}
  for i = 1, N * N do cnt[i] = 0 for d = 1, 3 do sum[d][i * 2 - 1], sum[d][i * 2] = 0, 0 end end
  for _, t in ipairs(tris) do
    local flow = M.triangleFlow(t.pos, t.uv)
    if flow then
      local uv = t.uv
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
  return out
end

-- ---- reading the triangles of the glass out of the car's .dae files ----
local function parseDae(path, wanted, glassMat, tris)
  local s = readFile(path)
  if not s then return end
  local yup = s:find('<up_axis>Y_UP', 1, true) ~= nil
  local unit = tonumber(s:match('<unit[^>]-meter="([^"]+)"')) or 1
  local matName, geomPos = {}, {}
  for id, nm in s:gmatch('<material id="([^"]+)" name="([^"]+)"') do matName[id] = nm end
  for p, id in s:gmatch('()<geometry id="([^"]+)"') do geomPos[id] = p end
  coroutine.yield()
  local pos = s:find('<library_visual_scenes', 1, true) or 1
  while true do
    local _, b, nm = s:find('<node [^>]-name="([^"]+)"', pos)
    if not b then break end
    pos = b + 1
    local fb = wanted[nm]
    if fb then
      local chunk = s:sub(b, s:find('</node>', b, true) or (b + 4000))
      local gid = chunk:match('<instance_geometry url="#([^"]+)"')
      local symGlass = {}
      for sym, tgt in chunk:gmatch('<instance_material symbol="([^"]+)" target="#([^"]+)"') do
        local mn = matName[tgt] or tgt
        if glassMat[mn] then symGlass[sym] = mn end
      end
      if gid and geomPos[gid] and next(symGlass) then
        local gp = geomPos[gid]
        local body = s:sub(gp, s:find('</geometry>', gp, true))
        local src = {}
        for id, txt in body:gmatch('<source id="([^"]+)"[^>]*>%s*<float_array[^>]*>([^<]*)<') do src[id] = txt end
        local psrc = body:match('<vertices[^>]*>%s*<input semantic="POSITION" source="#([^"]+)"')
        local P = psrc and src[psrc] and nums(src[psrc])
        local m = nums(chunk:match('<matrix[^>]*>([^<]+)<') or '1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1')
        local ox, oy, oz = 0, 0, 0
        if type(fb) == 'table' and fb.pos then ox, oy, oz = fb.pos.x or 0, fb.pos.y or 0, fb.pos.z or 0 end
        for attrs, inner in body:gmatch('<triangles([^>]*)>(.-)</triangles>') do
          local mn = symGlass[attrs:match('material="([^"]+)"') or '']
          if mn and P then
            local stride, vo, to, tsrc = 0, nil, nil, nil
            for inp in inner:gmatch('<input([^>]*)/>') do
              local sem, sc = inp:match('semantic="([^"]+)"'), inp:match('source="#([^"]+)"')
              local off = tonumber(inp:match('offset="(%d+)"')) or 0
              if off + 1 > stride then stride = off + 1 end
              if sem == 'VERTEX' then vo = off elseif sem == 'TEXCOORD' and not to then to, tsrc = off, sc end      -- the first texture coordinate set: the one a base colour map reads
            end
            local idx = nums(inner:match('<p>([^<]*)</p>') or '')
            if vo and to and src[tsrc] and #idx >= stride * 3 then
              local T = nums(src[tsrc])
              for k = 0, #idx / stride - 1, 3 do
                local t = { pos = {}, uv = {}, mat = mn }
                for c = 0, 2 do
                  local vi, ti = idx[(k + c) * stride + vo + 1] * 3, idx[(k + c) * stride + to + 1] * 2
                  local x, y, z = P[vi + 1], P[vi + 2], P[vi + 3]
                  local wx = (m[1] * x + m[2] * y + m[3] * z + m[4]) * unit
                  local wy = (m[5] * x + m[6] * y + m[7] * z + m[8]) * unit
                  local wz = (m[9] * x + m[10] * y + m[11] * z + m[12]) * unit
                  if yup then wy, wz = -wz, wy end
                  t.pos[c * 3 + 1], t.pos[c * 3 + 2], t.pos[c * 3 + 3] = wx + ox, wy + oy, wz + oz
                  t.uv[c * 2 + 1], t.uv[c * 2 + 2] = T[ti + 1], T[ti + 2]
                end
                tris[#tris + 1] = t
              end
            end
          end
        end
        coroutine.yield()
      end
    end
  end
end

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
    local tris = {}
    local files = {}
    pcall(function() files = FS:findFiles(vd.vehicleDirectory, '*.dae', -1, false, false) or {} end)
    for _, path in ipairs(files) do
      local ok, err = pcall(parseDae, path, wanted, glassMat, tris)
      if not ok then log('W', TAG, 'could not read ' .. path .. ': ' .. tostring(err)) end
      coroutine.yield()
    end
    local byMat = {}
    for _, t in ipairs(tris) do byMat[t.mat] = byMat[t.mat] or {} table.insert(byMat[t.mat], t) end
    local out = {}
    for mn, list in pairs(byMat) do out[mn] = M.field(list) end
    cache[key] = out
    log('I', TAG, tostring(vd.vehicleDirectory) .. ': ' .. #tris .. ' glass triangles in ' .. #mats .. ' material(s)')
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
  for _, kind in ipairs({ 'g', 'b', 'r' }) do
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
