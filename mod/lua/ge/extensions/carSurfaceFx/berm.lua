-- Car Surface FX: the berms of a rut. For each chunk of rut that ruts.lua makes, a strip of soil on each side of the track (a ProceduralMesh with a small ridge across, built in memory,
-- its vertices dropped onto the ground so it follows slope and camber). The shape is bermrules.lua (tested); the code that makes a mesh follows fluidmesh.lua (2 builds a pass, a time
-- budget, recycling, off for good when the engine refuses a mesh). Materials: art/surfacefx/marks/berm.materials.json (tools/make_berm_materials.py), opaque soil from the rut textures.
local M = {}

local rules = require('carSurfaceFx/bermrules')
local mm = require('carSurfaceFx/markMaterials')

local FILE = '/art/surfacefx/marks/berm.materials.json'
local MAX_BUILDS, BUDGET = 2, 0.006

local ring, head, n = {}, 0, 0                       -- the meshes made (a ring of ProceduralMesh objects)
local pending, pendingN = {}, 0                      -- strips waiting for a build pass
local failed                                         -- why berms are off (the engine refused a mesh), nil while they work
local count = 0
local stats = { built = 0, deleted = 0, queued = 0 }
M.stats = stats

local function delete(o) if o then pcall(function() o:delete() end) end end

local function groundZ(x, y, zTop)
  local ok, d = pcall(function() return castRayStatic(vec3(x, y, zTop), vec3(0, 0, -1), 6) end)
  if ok and type(d) == 'number' and d < 6 then return zTop - d end
end

local ensured = {}
local function ensure(name)
  if ensured[name] then return true end
  if not (scenetree and scenetree.findObject(name)) and loadJsonMaterialsFile then pcall(loadJsonMaterialsFile, FILE) end
  local ok = mm.ensure(name, FILE)
  ensured[name] = ok or nil
  return ok
end

-- ask for the berms of a chunk ({ kind, points }) on a rut `width` wide, `depth` pressed, pass `layer`
function M.add(cfg, chunk, width, depth, layer)
  if failed or not cfg.enabled then return end
  local h, lip = rules.size(chunk.kind, depth, layer, cfg)
  if h <= 0.004 then return end
  if pendingN >= 30 then return end
  pendingN = pendingN + 1
  pending[pendingN] = { kind = chunk.kind, points = chunk.points, half = width * 0.5, lip = lip, h = h }
  stats.queued = stats.queued + 1
end

local function build(job, cfg)
  local s = rules.strip(job.points, job.half, job.lip, job.h, cfg.lift)
  if not s then return true end
  local material = 'csfx_berm_' .. job.kind
  if not ensure(material) then failed = 'material ' .. material return false end
  local o = s.origin
  local verts, uvs, normals, faces = {}, {}, {}, {}
  for i, v in ipairs(s.verts) do
    local gz = groundZ(o[1] + v[1], o[2] + v[2], o[3] + v[3] + 1.5)
    local est = v[3] - v[7] - cfg.lift                                    -- the path's own ground height here, relative to the origin
    local z = (gz and math.max(est - 0.3, math.min(est + 0.3, gz - o[3])) or est) + cfg.lift + v[7]
    verts[i] = { x = v[1], y = v[2], z = z }
    uvs[i] = { u = s.uvs[i][1], v = s.uvs[i][2] }
    normals[i] = { x = v[4], y = v[5], z = v[6] }
  end
  for i, f in ipairs(s.faces) do faces[i] = { v = f, u = f, n = f } end
  count = count + 1
  local ok, mesh = pcall(function()
    local proc = createObject('ProceduralMesh')
    proc:registerObject('csfx_berm_' .. count)
    proc.canSave = false
    pcall(function() scenetree.MissionGroup:addObject(proc) end)
    proc:createMesh({ { { verts = verts, uvs = uvs, normals = normals, faces = faces, material = material } } })
    proc:setPosition(vec3(o[1], o[2], o[3]))
    return proc
  end)
  if not (ok and mesh) then failed = tostring(mesh) return false end
  local max = math.max(8, math.floor(cfg.maxBerms))
  head = (head % max) + 1
  if ring[head] then delete(ring[head]) stats.deleted = stats.deleted + 1 end
  ring[head] = mesh
  if n < max then n = n + 1 end
  stats.built = stats.built + 1
  return true
end

-- every frame (cheap when nothing is queued): make a few strips within the time budget
function M.update(cfg)
  if failed or pendingN == 0 then return end
  local t0, builds = os.clock(), 0
  while pendingN > 0 and builds < MAX_BUILDS and os.clock() - t0 < BUDGET do
    local job = table.remove(pending, 1)
    pendingN = pendingN - 1
    builds = builds + 1
    if not build(job, cfg) then break end
  end
end

function M.clear()
  for i = 1, n do delete(ring[i]) ring[i] = nil end
  ring, head, n, pending, pendingN = {}, 0, 0, {}, 0
end

function M.available() return failed == nil end
function M.why() return failed end
function M.retry() failed = nil ensured = {} end
function M.count() return n end
function M.status()
  return string.format('berms %d (built %d, deleted %d, queued %d)%s', n, stats.built, stats.deleted, stats.queued, failed and (', OFF: ' .. tostring(failed)) or '')
end

return M
