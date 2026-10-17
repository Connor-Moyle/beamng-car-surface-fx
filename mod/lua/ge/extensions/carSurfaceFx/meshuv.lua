-- Ported from Enhanced Skid Marks (Surface FX) by Fatkiwi (the same author), renamed for Car Surface FX.
--[[ ------------------------------------------------------------------------
  carSurfaceFx/meshuv.lua  -  GE side: works out, for ANY spawned vehicle, where each
  jbeam node sits on the car's paint texture. no per-vehicle data files.
  by Fatkiwi

  every vehicle ships its source mesh as plain COLLADA (.dae) next to the compiled
  .cdae, so at spawn we read the .dae(s) in the vehicle's own folder, pull the
  triangles of the meshes that are ACTUALLY FITTED (vdata.flexbodies) and that use
  a paint material, and match each jbeam node's rest position to the nearest paint
  triangle corner. result per node: its UV, plus how a direction in car space maps
  onto the texture there (so a scrape can be drawn the way it really ran, at its
  real size).

  UV SET: the SECOND texcoord set (set="1") - the unique, un-mirrored "skin"
  layout liveries are painted in. the first set is mirrored left/right on most
  cars (a scratch on one door would show on both), the later ones are junk.

  pure text parsing, no FFI. a .dae can be 60MB, so the build runs as a coroutine
  spread over frames (M.tick) and the result is cached per model + fitted meshes.
  a vehicle with no .dae at all (some mods ship only .cdae) simply gets no map.
------------------------------------------------------------------------- --]]

local M = {}
local logTag = 'carSurfaceFx_meshuv'

local CELL     = 0.1          -- spatial hash cell (m)
local RADIUS   = 0.3          -- a node only maps if a paint corner is within this (m)
local BUDGET   = 6            -- ms of work per frame
local cache    = {}           -- key -> lut
local jobs     = {}           -- running coroutines: { co=, cb= }

local floor, sqrt = math.floor, math.sqrt

local function parseNums(s)
  local t, n = {}, 0
  for tok in s:gmatch('[^%s]+') do n = n + 1; t[n] = tonumber(tok) end
  return t
end

-- one <triangles>/<polylist> block -> { sym=, vo=, to=, tsrc=, stride=, p=, vcount= } (text kept, parsed later)
local function readPrims(body, tag, out)
  for attrs, inner in body:gmatch('<' .. tag .. '([^>]*)>(.-)</' .. tag .. '>') do
    local pr = { sym = attrs:match('material="([^"]+)"'), stride = 0 }
    for inp in inner:gmatch('<input([^>]*)/>') do
      local sem, src = inp:match('semantic="([^"]+)"'), inp:match('source="#([^"]+)"')
      local off = tonumber(inp:match('offset="(%d+)"')) or 0
      if off + 1 > pr.stride then pr.stride = off + 1 end
      if sem == 'VERTEX' then pr.vo = off
      elseif sem == 'TEXCOORD' and inp:match('set="1"') then pr.to = off; pr.tsrc = src end
    end
    pr.p = inner:match('<p>([^<]*)</p>')
    pr.vcount = inner:match('<vcount>([^<]*)</vcount>')
    if pr.sym and pr.vo and pr.to and pr.p then out[#out + 1] = pr end
  end
end

-- read every fitted paint mesh out of one .dae into the flat corner arrays C (3 consecutive = 1 triangle)
local function parseDae(path, wanted, paintMat, C, used)
  local s = readFile(path)
  if not s then return end
  local yup  = s:find('<up_axis>Y_UP', 1, true) ~= nil
  local unit = tonumber(s:match('<unit[^>]-meter="([^"]+)"')) or 1
  local matName, geomPos = {}, {}
  for id, nm in s:gmatch('<material id="([^"]+)" name="([^"]+)"') do matName[id] = nm end
  for p, id in s:gmatch('()<geometry id="([^"]+)"') do geomPos[id] = p end
  coroutine.yield()

  local geoms = {}                                  -- gid -> { P=, prims=, T={} } (mirrored instances share one)
  local pos = s:find('<library_visual_scenes', 1, true) or 1
  while true do
    local _, b, nm = s:find('<node [^>]-name="([^"]+)"', pos)
    if not b then break end
    pos = b + 1
    local fb = wanted[nm]
    if fb then
      local chunk = s:sub(b, s:find('</node>', b, true) or (b + 4000))
      local gid = chunk:match('<instance_geometry url="#([^"]+)"')
      local symPaint, any = {}, false
      for sym, tgt in chunk:gmatch('<instance_material symbol="([^"]+)" target="#([^"]+)"') do
        local mn = matName[tgt] or tgt
        if paintMat[mn] then symPaint[sym] = mn; any = true end
      end
      if gid and any and geomPos[gid] then
        local g = geoms[gid]
        if not g then
          local gp = geomPos[gid]
          local body = s:sub(gp, s:find('</geometry>', gp, true))
          g = { src = {}, prims = {}, T = {} }
          for id, txt in body:gmatch('<source id="([^"]+)"[^>]*>%s*<float_array[^>]*>([^<]*)<') do g.src[id] = txt end
          local psrc = body:match('<vertices[^>]*>%s*<input semantic="POSITION" source="#([^"]+)"')
          g.P = psrc and g.src[psrc] and parseNums(g.src[psrc])
          readPrims(body, 'triangles', g.prims); readPrims(body, 'polylist', g.prims)
          geoms[gid] = g
        end
        local m = parseNums(chunk:match('<matrix[^>]*>([^<]+)<') or '1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1')
        local ox, oy, oz = 0, 0, 0
        if type(fb) == 'table' and fb.pos then ox, oy, oz = fb.pos.x or 0, fb.pos.y or 0, fb.pos.z or 0 end
        for _, pr in ipairs(g.prims) do
          local mn = symPaint[pr.sym]
          if mn and g.P and g.src[pr.tsrc] then
            local T = g.T[pr.tsrc]; if not T then T = parseNums(g.src[pr.tsrc]); g.T[pr.tsrc] = T end
            local idx = type(pr.p) == 'table' and pr.p or parseNums(pr.p); pr.p = idx
            local vc = pr.vcount and (type(pr.vcount) == 'table' and pr.vcount or parseNums(pr.vcount)); pr.vcount = vc
            local P, st, vo, to = g.P, pr.stride, pr.vo, pr.to
            local n = #C.x
            local function corner(k)                 -- k = 0-based corner number in the <p> stream
              local vi, ti = idx[k * st + vo + 1] * 3, idx[k * st + to + 1] * 2
              local x, y, z = P[vi + 1], P[vi + 2], P[vi + 3]
              local wx = (m[1] * x + m[2] * y + m[3] * z + m[4]) * unit
              local wy = (m[5] * x + m[6] * y + m[7] * z + m[8]) * unit
              local wz = (m[9] * x + m[10] * y + m[11] * z + m[12]) * unit
              if yup then wy, wz = -wz, wy end
              n = n + 1
              C.x[n], C.y[n], C.z[n], C.u[n], C.v[n] = wx + ox, wy + oy, wz + oz, T[ti + 1], T[ti + 2]
            end
            if vc then                                -- polylist: fan-triangulate each polygon
              local k = 0
              for _, cnt in ipairs(vc) do
                for i = 1, cnt - 2 do corner(k); corner(k + i); corner(k + i + 1) end
                k = k + cnt
              end
            else
              for k = 0, #idx / st - 1 do corner(k) end
            end
            used[mn] = (used[mn] or 0) + 1
          end
        end
        coroutine.yield()
      end
    end
  end
end

local function cellKey(ix, iy, iz) return (ix + 512) * 1048576 + (iy + 512) * 1024 + (iz + 512) end

-- the whole build. returns lut = { nodes = { [cid] = {u,v, jux,juy,juz, jvx,jvy,jvz, s} }, mats = { [mapTo]=true } }
local function build(dir, nodes, flexbodies, paintMat)
  local wanted = {}
  for _, f in pairs(flexbodies) do if f.mesh then wanted[f.mesh] = f end end
  local C, used = { x = {}, y = {}, z = {}, u = {}, v = {} }, {}
  for _, path in ipairs(FS:findFiles(dir, '*.dae', -1, false, false)) do
    local ok, err = pcall(parseDae, path, wanted, paintMat, C, used)
    if not ok then log('W', logTag, ('could not read %s: %s'):format(path, tostring(err))) end
    coroutine.yield()
  end
  local n = #C.x - #C.x % 3
  -- faces a livery must not reach (door jambs, inner skins, undersides) are collapsed to a single
  -- point in this UV set: they have no place on the texture, so they never go in the grid
  local grid = {}
  for a = 1, n, 3 do
    local area = (C.u[a+1] - C.u[a]) * (C.v[a+2] - C.v[a]) - (C.u[a+2] - C.u[a]) * (C.v[a+1] - C.v[a])
    if area > 1e-9 or area < -1e-9 then
      for i = a, a + 2 do
        local k = cellKey(floor(C.x[i] / CELL), floor(C.y[i] / CELL), floor(C.z[i] / CELL))
        local c = grid[k]; if not c then c = {}; grid[k] = c end
        c[#c + 1] = i
      end
    end
  end
  coroutine.yield()

  local lut, count, R = {}, 0, math.ceil(RADIUS / CELL)
  for _, nd in pairs(nodes) do
    local p = nd.pos
    if p and nd.cid then
      local best, bd = nil, RADIUS * RADIUS
      local cx, cy, cz = floor(p.x / CELL), floor(p.y / CELL), floor(p.z / CELL)
      for ix = cx - R, cx + R do for iy = cy - R, cy + R do for iz = cz - R, cz + R do
        local c = grid[cellKey(ix, iy, iz)]
        if c then for _, i in ipairs(c) do
          local dx, dy, dz = C.x[i] - p.x, C.y[i] - p.y, C.z[i] - p.z
          local d = dx * dx + dy * dy + dz * dz
          if d < bd then bd = d; best = i end
        end end
      end end end
      if best then
        -- the triangle this corner belongs to gives the car-space -> texture-space mapping here:
        -- for a direction d lying in the panel, (du,dv) = (Ju.d, Jv.d)
        local a = best - (best - 1) % 3
        local e1x, e1y, e1z = C.x[a+1] - C.x[a], C.y[a+1] - C.y[a], C.z[a+1] - C.z[a]
        local e2x, e2y, e2z = C.x[a+2] - C.x[a], C.y[a+2] - C.y[a], C.z[a+2] - C.z[a]
        local du1, dv1, du2, dv2 = C.u[a+1] - C.u[a], C.v[a+1] - C.v[a], C.u[a+2] - C.u[a], C.v[a+2] - C.v[a]
        local g11, g12, g22 = e1x*e1x + e1y*e1y + e1z*e1z, e1x*e2x + e1y*e2y + e1z*e2z, e2x*e2x + e2y*e2y + e2z*e2z
        local det = g11 * g22 - g12 * g12
        local e = { C.u[best], C.v[best], 0, 0, 0, 0, 0, 0, 0 }
        if det > 1e-14 then
          local Ax, Ay, Az = (g22*e1x - g12*e2x) / det, (g22*e1y - g12*e2y) / det, (g22*e1z - g12*e2z) / det
          local Bx, By, Bz = (g11*e2x - g12*e1x) / det, (g11*e2y - g12*e1y) / det, (g11*e2z - g12*e1z) / det
          e[3], e[4], e[5] = Ax*du1 + Bx*du2, Ay*du1 + By*du2, Az*du1 + Bz*du2
          e[6], e[7], e[8] = Ax*dv1 + Bx*dv2, Ay*dv1 + By*dv2, Az*dv1 + Bz*dv2
          e[9] = sqrt((e[3]*e[3] + e[4]*e[4] + e[5]*e[5] + e[6]*e[6] + e[7]*e[7] + e[8]*e[8]) / 2)   -- texture units per metre
        end
        if e[9] > 0 and e[9] < 5 then lut[nd.cid] = e; count = count + 1 end   -- >5/m = a degenerate sliver, not a real spot
      end
    end
  end
  return { nodes = lut, count = count, mats = used, corners = n }
end

-- ask for a vehicle's map. cb(lut) is called later (lut.count == 0 when there's nothing usable).
-- paintMat = { [dae material name] = true } - which materials count as paint.
function M.request(vehId, paintMat, cb)
  local vd = core_vehicle_manager.getVehicleData(vehId)
  if not vd or not vd.vdata or not vd.vdata.nodes then return cb(nil) end
  local names = {}
  for _, f in pairs(vd.vdata.flexbodies or {}) do if f.mesh then names[#names + 1] = f.mesh end end
  table.sort(names)
  local mats = tableKeys(paintMat); table.sort(mats)
  local key = tostring(vd.vehicleDirectory) .. '|' .. table.concat(mats, ',') .. '|' .. table.concat(names, ',')
  if cache[key] then return cb(cache[key]) end
  local co = coroutine.create(function()
    local lut = build(vd.vehicleDirectory, vd.vdata.nodes, vd.vdata.flexbodies or {}, paintMat)
    cache[key] = lut
    log('I', logTag, ('%s: %d of %d nodes mapped onto the paint (%d triangle corners)'):format(
      tostring(vd.vehicleDirectory), lut.count, tableSize(vd.vdata.nodes), lut.corners))
    return lut
  end)
  jobs[#jobs + 1] = { co = co, cb = cb }
end

-- run the pending builds a few ms at a time (called from carSurfaceFx/scratch.lua's onUpdate)
function M.tick()
  local job = jobs[1]
  if not job then return end
  local timer = hptimer()
  repeat
    local ok, res = coroutine.resume(job.co)
    if coroutine.status(job.co) == 'dead' then
      table.remove(jobs, 1)
      if not ok then log('E', logTag, 'build failed: ' .. tostring(res)); res = nil end
      job.cb(res)
      return
    end
  until timer:stop() > BUDGET
end

function M.busy() return jobs[1] ~= nil end

return M
