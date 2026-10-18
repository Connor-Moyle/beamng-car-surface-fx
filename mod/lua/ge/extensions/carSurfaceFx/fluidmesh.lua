-- Car Surface FX: the glossy leak puddles. A puddle of oil, coolant or fuel is a thin translucent plane (a ProceduralMesh built in memory, its corners dropped onto the ground so it
-- follows slope and camber) with a very smooth, tinted material, so it mirrors the sky like a rain puddle; oil gets a second plane above it with a rainbow sheen. The decal path in
-- fluids.lua stays for the drip spots of a moving car and as the fallback when the engine refuses a mesh. Materials: art/surfacefx/fluids/main.materials.json (tools/make_fluid_assets.py).
local M = {}

local mm = require('carSurfaceFx/markMaterials')

local FILE = '/art/surfacefx/fluids/main.materials.json'
local MATERIAL = { oil = 'csfx_puddle_oil', coolant = 'csfx_puddle_coolant', fuel = 'csfx_puddle_fuel' }
local SHEEN = 'csfx_puddle_sheen'
local GRID = 5                                  -- corners across a plane
local LIFT, SHEEN_LIFT = 0.03, 0.045            -- metres above the ground (2 cm z-fights at a distance)
local MAX_BUILDS, BUDGET = 2, 0.006             -- planes made per pass, and the seconds a pass may use

local recs = {}                                 -- puddle -> { obj, sheen, gen, kind, built (radius the corners were sampled for), r, x, y }
local count = 0
local failed                                    -- why meshes are off (the engine refused one), nil while they work
local stats = { built = 0, deleted = 0, rejected = 0 }
M.stats = stats

local function delete(o) if o then pcall(function() o:delete() end) end end
local function drop(p, rec)
  delete(rec.obj) delete(rec.sheen)
  recs[p] = nil
  p.meshed = nil
  stats.deleted = stats.deleted + 1
end

local function groundZ(x, y, zTop)
  local ok, d = pcall(function() return castRayStatic(vec3(x, y, zTop), vec3(0, 0, -1), 40) end)
  if ok and type(d) == 'number' and d < 40 then return zTop - d end
  local ok2, z = pcall(function() return be:getSurfaceHeightBelow(vec3(x, y, zTop)) end)
  if ok2 and type(z) == 'number' and z > -1e5 then return z end
end

-- the materials exist (loaded by the game from the mod's art folder, else made from the file)
local ensured = {}
local function ensure(name)
  if ensured[name] then return true end
  if not (scenetree and scenetree.findObject(name)) and loadJsonMaterialsFile then pcall(loadJsonMaterialsFile, FILE) end
  local ok = mm.ensure(name, FILE)
  ensured[name] = ok or nil
  return ok
end

-- a plane of this radius round the puddle, in world axes, turned by `angle`: verts, uvs, faces of a ProceduralMesh
local function planeData(p, radius, angle)
  local n, verts, uvs, faces = GRID, {}, {}, {}
  local ca, sa, D = math.cos(angle), math.sin(angle), radius * 2
  for iy = 0, n - 1 do
    for ix = 0, n - 1 do
      local lx, ly = (-0.5 + ix / (n - 1)) * D, (-0.5 + iy / (n - 1)) * D
      local vx, vy = lx * ca - ly * sa, lx * sa + ly * ca
      local z = groundZ(p.x + vx, p.y + vy, p.z + 2)
      local dz = z and math.max(-0.12, math.min(0.12, z - p.z)) or 0
      verts[#verts + 1] = { x = vx, y = vy, z = dz }
      uvs[#uvs + 1] = { u = ix / (n - 1), v = iy / (n - 1) }
    end
  end
  for iy = 0, n - 2 do
    for ix = 0, n - 2 do
      local i = iy * n + ix
      for _, c in ipairs({ i, i + 1, i + n + 1, i, i + n + 1, i + n }) do faces[#faces + 1] = { v = c, u = c, n = 0 } end
    end
  end
  return verts, uvs, faces
end

local function makePlane(name, p, radius, angle, material, lift)
  if not ensure(material) then return nil, 'material ' .. material end
  local verts, uvs, faces = planeData(p, radius, angle)
  local ok, o = pcall(function()
    local proc = createObject('ProceduralMesh')
    proc:registerObject(name)
    proc.canSave = false
    pcall(function() scenetree.MissionGroup:addObject(proc) end)
    proc:createMesh({ { { verts = verts, uvs = uvs, normals = { { x = 0, y = 0, z = 1 } }, faces = faces, material = material } } })
    proc:setPosition(vec3(p.x, p.y, p.z + lift))
    return proc
  end)
  if ok and o then return o end
  return nil, tostring(o)
end

local function build(p, radius, withSheen)
  count = count + 1
  local o, why = makePlane('csfx_pd_' .. count, p, radius, p.angle or 0, MATERIAL[p.kind], LIFT)
  if not o then failed = why return nil end
  local s
  if withSheen then s = makePlane('csfx_pd_s' .. count, p, radius, (p.angle or 0) + 1.3, SHEEN, SHEEN_LIFT) end
  stats.built = stats.built + 1
  return { obj = o, sheen = s, gen = p.gen, kind = p.kind, built = radius, k = nil, x = p.x, y = p.y }
end

local function scale(rec, k)
  pcall(function() rec.obj:setScale(vec3(k, k, 1)) if rec.sheen then rec.sheen:setScale(vec3(k, k, 1)) end end)
  rec.k = k
end

-- the rainbow bands shift with the view in a real film: a cheap fake turns the sheen plane about its normal with the camera's bearing to the puddle (and a slow drift), only for puddles near
-- the camera. If the engine takes no rotation for the object the call fails quietly and the sheen stays still.
local NEAR = 15
local function turnSheen(rec, p, camX, camY)
  local dx, dy = p.x - camX, p.y - camY
  if dx * dx + dy * dy > NEAR * NEAR then return end
  local a = (math.atan2 or math.atan)(dy, dx) * 0.7 + os.clock() * 0.04
  if rec.turn and math.abs(a - rec.turn) < 0.05 then return end
  rec.turn = a
  pcall(function() rec.sheen:setPosRot(p.x, p.y, p.z + SHEEN_LIFT, 0, 0, math.sin(a / 2), math.cos(a / 2)) end)
  if rec.k then pcall(function() rec.sheen:setScale(vec3(rec.k, rec.k, 1)) end) end
end

function M.available() return failed == nil end
function M.why() return failed end

-- every 0.25 s: put a plane under each puddle near the camera, grow it with the puddle, take it away when the puddle is recycled or far. `fade(i)` is the ring's fade (0..1) of slot i.
-- Puddles that have a plane carry p.meshed = true so the decal pass leaves them out.
function M.sync(store, cfg, camX, camY, fade)
  if failed then return end
  local t0 = os.clock()
  local builds, seen = 0, {}
  local cr2 = cfg.cullRadius * cfg.cullRadius
  for i = 1, store.count do
    local p = store.list[i]
    if p and p.r > 0 and not p.stain and MATERIAL[p.kind] and cfg.kinds[p.kind] and cfg.kinds[p.kind].enabled then
      local rec = recs[p]
      if rec and (rec.gen ~= p.gen or rec.kind ~= p.kind) then drop(p, rec) rec = nil end
      local near = true
      if camX then local dx, dy = p.x - camX, p.y - camY near = dx * dx + dy * dy <= cr2 end
      local r = p.r * (fade and fade(i) or 1)
      if near and r >= 0.04 then
        if rec and rec.built < p.r * 0.95 then drop(p, rec) rec = nil end             -- outgrew the corners it was sampled for
        if not rec and builds < MAX_BUILDS and os.clock() - t0 < BUDGET then
          rec = build(p, math.max(p.r * 1.5, 0.3), p.kind == 'oil' and cfg.sheen ~= false)
          if rec then recs[p] = rec builds = builds + 1 end
        end
        if rec then
          seen[p] = true
          local k = r / rec.built
          if not rec.k or math.abs(k - rec.k) > 0.02 * math.max(1, k) then scale(rec, k) end
          if math.abs(p.x - rec.x) + math.abs(p.y - rec.y) > 0.03 then
            rec.x, rec.y = p.x, p.y
            pcall(function() rec.obj:setPosition(vec3(p.x, p.y, p.z + LIFT)) if rec.sheen then rec.sheen:setPosition(vec3(p.x, p.y, p.z + SHEEN_LIFT)) end end)
          end
          if rec.sheen and camX then turnSheen(rec, p, camX, camY) end
          p.meshed = true
        end
      end
    end
  end
  for p, rec in pairs(recs) do                                                           -- planes whose puddle went (recycled, dried, faded, far)
    if not seen[p] then drop(p, rec) end
  end
end

function M.clear()
  for p, rec in pairs(recs) do drop(p, rec) end
end

function M.count() local n = 0 for _ in pairs(recs) do n = n + 1 end return n end

function M.status()
  return string.format('planes %d (built %d, deleted %d)%s', M.count(), stats.built, stats.deleted, failed and (', OFF: ' .. tostring(failed)) or '')
end

-- carSurfaceFx_fluids.meshRetry(): after the engine refused a plane, try again (a test)
function M.retry() failed = nil ensured = {} end

return M
