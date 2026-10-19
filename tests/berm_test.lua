-- ruts' berms: the lip strip shape (bermrules.lua)
local B = require('carSurfaceFx/bermrules')
local cfg = B.defaults()

local h, w = B.size('mud', 1, 1, cfg)
assert(h > B.size('gravel', 1, 1, cfg) and B.size('mud', 1, 2, cfg) > h and B.size('mud', 0.5, 1, cfg) < h and w > 0, 'softer ground and more passes raise a higher lip, a lighter wheel a lower one')
assert(B.size('mud', 9, 1, cfg) == B.size('mud', 1.5, 1, cfg), 'the depth is capped')
assert(cfg.enabled == false, 'berms are off until proven')

assert(B.strip({ { 0, 0, 0 } }, 0.4, 0.3, 0.1, 0) == nil and B.strip({ { 0, 0, 0 }, { 0, 0, 0 } }, 0.4, 0.3, 0.1, 0) == nil and B.strip({ { 0, 0, 0 }, { 1, 0, 0 } }, 0, 0.3, 0.1, 0) == nil
  and B.strip({ { 0, 0, 0 }, { 1, 0, 0 } }, 0.4, 0.3, 0, 0) == nil, 'one point, a standing point, no width or no height make no strip')

-- a straight path along +x on level ground: the left lip is at +y, the right at -y
local pts = { { 10, 5, 2 }, { 10.6, 5, 2 }, { 11.2, 5, 2 }, { 11.8, 5, 2 } }
local s = B.strip(pts, 0.4, 0.3, 0.1, 0.01)
-- 6 vertices per sample; per gap: 2 lips x 2 columns x 2 triangles x 3 indices
assert(s and #s.verts == 4 * 6 and #s.uvs == #s.verts and #s.faces == 3 * 2 * 2 * 2 * 3 and s.n == 4, 'vertex and face counts: ' .. #s.verts .. ' ' .. #s.faces)
local v1, v2, v3 = s.verts[1], s.verts[2], s.verts[3]
assert(math.abs(v1[2] - 0.4) < 1e-9 and math.abs(v2[2] - 0.55) < 1e-9 and math.abs(v3[2] - 0.7) < 1e-9, 'left lip: inner foot, crest, outer foot out from the track')
assert(math.abs(v2[3] - 0.11) < 1e-9 and math.abs(v1[3] - 0.01) < 1e-9 and math.abs(v3[3] - 0.01) < 1e-9, 'the crest is h above the feet, the feet lift above the ground')
assert(math.abs(s.verts[4][2] + 0.4) < 1e-9 and math.abs(s.verts[6][2] + 0.7) < 1e-9, 'right lip on the other side')
assert(s.origin[1] == 10 and s.verts[1][1] == 0 and math.abs(s.verts[19][1] - 1.8) < 1e-9, 'vertices are relative to the first point')
assert(math.abs(s.uvs[19][2] - 1.8) < 1e-9 and s.uvs[1][2] == 0 and s.uvs[2][1] == 0.5, 'v runs along the path in metres, u across the lip')

-- every face is valid, and faces up (counter-clockwise seen from above)
local upCount, count = 0, 0
for i = 1, #s.faces, 3 do
  local a, b, c = s.verts[s.faces[i] + 1], s.verts[s.faces[i + 1] + 1], s.verts[s.faces[i + 2] + 1]
  assert(a and b and c, 'face index in range')
  local ux, uy, vx, vy = b[1] - a[1], b[2] - a[2], c[1] - a[1], c[2] - a[2]
  if ux * vy - uy * vx > 0 then upCount = upCount + 1 end
  count = count + 1
end
assert(upCount == count, 'all faces wind counter-clockwise seen from above: ' .. upCount .. '/' .. count)
for _, v in ipairs(s.verts) do assert(v[6] > 0.5, 'normals point up') end

-- a curve: the strip follows the path (the left lip stays left of the heading)
local curve = { { 0, 0, 0 }, { 1, 0, 0 }, { 1.7, 0.7, 0 }, { 1.7, 1.7, 0 } }
local c = B.strip(curve, 0.3, 0.2, 0.05, 0)
assert(c and c.verts[19][1] < 1.7 and c.verts[19][2] > 0.5, 'left of a path heading +y is toward -x')

-- the builder against a mocked game: strips are queued, built within the budget, the ring recycles, and an engine that refuses a mesh switches berms off
local made, deleted = {}, 0
local saved = { createObject = createObject, castRayStatic = castRayStatic, scenetree = scenetree, vec3 = vec3, loadJsonMaterialsFile = loadJsonMaterialsFile }
vec3 = function(x, y, z) return { x = x, y = y, z = z } end
castRayStatic = function(p) return p.z - 2.05 end                                -- the ground is at z = 2.05 (5 cm above the path)
scenetree = { findObject = function() return {} end, MissionGroup = { addObject = function() end } }
local refuse = false
createObject = function()
  local o = { meshes = 0 }
  function o:registerObject() end
  function o:createMesh(m) if refuse then error('no mesh') end self.mesh = m made[#made + 1] = self end
  function o:setPosition() end
  function o:delete() deleted = deleted + 1 end
  return o
end
package.loaded['carSurfaceFx/berm'] = nil
package.loaded['carSurfaceFx/markMaterials'] = { ensure = function() return true end }
local berm = require('carSurfaceFx/berm')
local on = B.defaults()
on.enabled, on.maxBerms = true, 8
local chunk = { kind = 'mud', points = pts }
berm.add({ enabled = false }, chunk, 0.8, 1, 1)
assert(berm.stats.queued == 0, 'nothing is queued while berms are off')
for _ = 1, 5 do berm.add(on, chunk, 0.8, 1, 1) end
berm.update(on)
assert(#made >= 1 and #made <= 2, 'at most two strips per pass: ' .. #made)
local grp = made[1].mesh[1][1]
assert(#grp.verts == 24 and #grp.faces == 72 and #grp.normals == 24 and grp.material == 'csfx_berm_mud' and grp.faces[1].v ~= nil, 'the mesh has the strip, its normals and the soil material')
assert(math.abs(grp.verts[2].z - 0.16) < 1e-6 and math.abs(grp.verts[1].z - 0.06) < 1e-6, 'a crest sits h above the ground the ray found, the foot a lift above it')
berm.update(on) berm.update(on) berm.update(on)
assert(berm.count() == 5 and berm.stats.built == 5, 'all queued strips get built over a few passes: ' .. berm.count())
for _ = 1, 10 do berm.add(on, chunk, 0.8, 1, 1) berm.update(on) berm.update(on) end
assert(berm.count() == 8 and deleted > 0, 'the ring holds maxBerms and recycles the oldest')
berm.clear()
assert(berm.count() == 0, 'clear removes them')
refuse = true
berm.add(on, chunk, 0.8, 1, 1) berm.update(on)
assert(not berm.available() and berm.why() ~= nil, 'a refused mesh switches berms off, with a reason')
berm.add(on, chunk, 0.8, 1, 1)
assert(berm.stats.queued == 16, 'and nothing more is queued')
createObject, castRayStatic, scenetree, vec3, loadJsonMaterialsFile = saved.createObject, saved.castRayStatic, saved.scenetree, saved.vec3, saved.loadJsonMaterialsFile
package.loaded['carSurfaceFx/berm'], package.loaded['carSurfaceFx/markMaterials'] = nil, nil
print('carSurfaceFx berm: ok')
