-- Car Surface FX: the triangles of chosen materials out of a car's source mesh (.dae, plain COLLADA text), in the car's own frame (jbeam axes: x left, y back, z up), with their
-- texture coordinates. Used by glassflow.lua (glass) and bodymap.lua (paint). Pure text parsing, no FFI. A .dae can be tens of megabytes, so read() is a coroutine body: it yields
-- between nodes, and the caller runs it a few milliseconds a frame.
--   read(path, wanted, matSet, uvSet, tris)
--     wanted  = { [flexbody mesh name] = flexbody } the meshes that are fitted on the car (their node names in the .dae)
--     matSet  = { [dae material name] = true }       which materials to keep
--     uvSet   = nil: the first texture coordinate set of each primitive; a number: the set with that index (the paint is on set 1)
--     tris    = list that gets { pos = { 9 numbers }, uv = { 6 numbers }, mat = material name, mesh = mesh name }
local M = {}

local function nums(s)
  local t, n = {}, 0
  for tok in s:gmatch('[^%s]+') do n = n + 1 t[n] = tonumber(tok) end
  return t
end
M.nums = nums

-- every <triangles> and <polylist> of a geometry: { material, stride, vo, to, tsrc, p = {numbers}, vcount = {numbers} or nil }
local function prims(body, uvSet)
  local out = {}
  for _, tag in ipairs({ 'triangles', 'polylist' }) do
    for attrs, inner in body:gmatch('<' .. tag .. '([^>]*)>(.-)</' .. tag .. '>') do
      local pr = { sym = attrs:match('material="([^"]+)"'), stride = 0 }
      for inp in inner:gmatch('<input([^>]*)/>') do
        local sem, src = inp:match('semantic="([^"]+)"'), inp:match('source="#([^"]+)"')
        local off = tonumber(inp:match('offset="(%d+)"')) or 0
        if off + 1 > pr.stride then pr.stride = off + 1 end
        if sem == 'VERTEX' then pr.vo = off
        elseif sem == 'TEXCOORD' and not pr.to then
          local set = tonumber(inp:match('set="(%d+)"'))
          if uvSet == nil or set == uvSet then pr.to, pr.tsrc = off, src end
        end
      end
      local p = inner:match('<p>([^<]*)</p>')
      if pr.sym and pr.vo and pr.to and p then
        pr.p = nums(p)
        local vc = inner:match('<vcount>([^<]*)</vcount>')
        pr.vcount = vc and nums(vc) or nil
        out[#out + 1] = pr
      end
    end
  end
  return out
end

function M.read(path, wanted, matSet, uvSet, tris)
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
      local symMat = {}
      for sym, tgt in chunk:gmatch('<instance_material symbol="([^"]+)" target="#([^"]+)"') do
        local mn = matName[tgt] or tgt
        if matSet[mn] then symMat[sym] = mn end
      end
      if gid and geomPos[gid] and next(symMat) then
        local gp = geomPos[gid]
        local body = s:sub(gp, s:find('</geometry>', gp, true))
        local src = {}
        for id, txt in body:gmatch('<source id="([^"]+)"[^>]*>%s*<float_array[^>]*>([^<]*)<') do src[id] = txt end
        local psrc = body:match('<vertices[^>]*>%s*<input semantic="POSITION" source="#([^"]+)"')
        local P = psrc and src[psrc] and nums(src[psrc])
        local m = nums(chunk:match('<matrix[^>]*>([^<]+)<') or '1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1')
        local ox, oy, oz = 0, 0, 0
        if type(fb) == 'table' and fb.pos then ox, oy, oz = fb.pos.x or 0, fb.pos.y or 0, fb.pos.z or 0 end
        local UVs = {}
        for _, pr in ipairs(prims(body, uvSet)) do
          local mn = symMat[pr.sym]
          if mn and P and src[pr.tsrc] then
            local T = UVs[pr.tsrc]
            if not T then T = nums(src[pr.tsrc]) UVs[pr.tsrc] = T end
            local idx, st = pr.p, pr.stride
            local function corner(k, t, c)                     -- corner k (0-based) of the primitive's index stream into slot c of triangle t
              local vi, ti = idx[k * st + pr.vo + 1] * 3, idx[k * st + pr.to + 1] * 2
              local x, y, z = P[vi + 1], P[vi + 2], P[vi + 3]
              local wx = (m[1] * x + m[2] * y + m[3] * z + m[4]) * unit
              local wy = (m[5] * x + m[6] * y + m[7] * z + m[8]) * unit
              local wz = (m[9] * x + m[10] * y + m[11] * z + m[12]) * unit
              if yup then wy, wz = -wz, wy end
              t.pos[c * 3 + 1], t.pos[c * 3 + 2], t.pos[c * 3 + 3] = wx + ox, wy + oy, wz + oz
              t.uv[c * 2 + 1], t.uv[c * 2 + 2] = T[ti + 1], T[ti + 2]
            end
            local function tri(a, b2, c2)
              local t = { pos = {}, uv = {}, mat = mn, mesh = nm }
              corner(a, t, 0) corner(b2, t, 1) corner(c2, t, 2)
              tris[#tris + 1] = t
            end
            if pr.vcount then                                    -- polylist: each polygon fanned into triangles
              local k = 0
              for _, cnt in ipairs(pr.vcount) do
                for i = 1, cnt - 2 do tri(k, k + i, k + i + 1) end
                k = k + cnt
              end
            else
              for k = 0, #idx / st - 3, 3 do tri(k, k + 1, k + 2) end
            end
          end
        end
        coroutine.yield()
      end
    end
  end
end

return M
