-- Car Surface FX: the berms of a rut (soil pushed up beside the wheel track): the shape of a lip strip along a chunk of the wheel path. Pure (no game calls), tested by tests/berm_test.lua.
-- berm.lua builds a ProceduralMesh from this. Each side of the track is a ridge of three vertices across (inner foot, crest, outer foot) at every path sample.
local M = {}

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end

M.HEIGHT = { mud = 0.10, snow = 0.12, sand = 0.06, dirt = 0.05, gravel = 0.035 }          -- crest height in metres at depth 1 (a normal car's wheel)
M.SPREAD = { mud = 0.30, snow = 0.28, sand = 0.40, dirt = 0.25, gravel = 0.22 }           -- width of one lip, in metres

function M.defaults() return { enabled = false, maxBerms = 120, heightScale = 1.0, lift = 0.01 } end

-- crest height and lip width for a rut of this kind, depth (rutrules.depth, 0..2.5) and layer (1..maxLayers)
function M.size(kind, depth, layer, cfg)
  local h = (M.HEIGHT[kind] or M.HEIGHT.dirt) * clamp(depth or 0, 0, 1.5) * (1 + 0.25 * ((layer or 1) - 1)) * (cfg.heightScale or 1)
  return h, M.SPREAD[kind] or M.SPREAD.dirt
end

-- points = { {x, y, z}, ... } (at least 2), halfWidth = half the rut's width. Returns nil for a path that cannot make a strip, else
--   { origin = {x, y, z}, verts = { {x, y, z, nx, ny, nz, rise} }, uvs = { {u, v} }, faces = { a, b, c, ... } (0-based, counter-clockwise from above), n = samples }
-- verts are relative to origin; z is the point's z plus `lift`, the crest `h` above it (`rise` is that part, 0 or h). Ground-follow is the caller's: it may move every vertex's z.
-- Vertex order: per sample, the left lip (inner, crest, outer) then the right lip.
function M.strip(points, halfWidth, lipWidth, h, lift)
  local n = points and #points or 0
  if n < 2 or not (halfWidth > 0) or not (lipWidth > 0) or not (h > 0) then return nil end
  local o = points[1]
  local verts, uvs, faces = {}, {}, {}
  local along = 0
  local offs = { halfWidth, halfWidth + lipWidth * 0.5, halfWidth + lipWidth }
  local hs = { 0, h, 0 }
  local lean = { -0.6, 0, 0.6 }                                          -- the normal leans into the track on the inner slope, away on the outer
  local up = { 0.8, 1, 0.8 }
  for i = 1, n do
    local a, b = points[math.max(1, i - 1)], points[math.min(n, i + 1)]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-6 then return nil end
    local lx, ly = -dy / len, dx / len                                   -- left of the heading
    if i > 1 then
      local p = points[i - 1]
      along = along + math.sqrt((points[i][1] - p[1]) ^ 2 + (points[i][2] - p[2]) ^ 2)
    end
    local base = points[i][3] + (lift or 0)
    for _, side in ipairs({ 1, -1 }) do
      for k = 1, 3 do
        local off = side * offs[k]
        verts[#verts + 1] = { points[i][1] - o[1] + lx * off, points[i][2] - o[2] + ly * off, base - o[3] + hs[k], lx * side * lean[k], ly * side * lean[k], up[k], hs[k] }
        uvs[#uvs + 1] = { (k - 1) / 2, along }
      end
    end
  end
  for i = 1, n - 1 do
    for side = 0, 1 do
      local a, b = (i - 1) * 6 + side * 3, i * 6 + side * 3                -- first vertex of this lip at sample i and at i + 1
      for k = 0, 1 do
        local v0, v1, w0, w1 = a + k, a + k + 1, b + k, b + k + 1
        if side == 0 then
          faces[#faces + 1] = v0 faces[#faces + 1] = w1 faces[#faces + 1] = v1
          faces[#faces + 1] = v0 faces[#faces + 1] = w0 faces[#faces + 1] = w1
        else
          faces[#faces + 1] = v0 faces[#faces + 1] = v1 faces[#faces + 1] = w1
          faces[#faces + 1] = v0 faces[#faces + 1] = w1 faces[#faces + 1] = w0
        end
      end
    end
  end
  return { origin = { o[1], o[2], o[3] }, verts = verts, uvs = uvs, faces = faces, n = n }
end

return M
