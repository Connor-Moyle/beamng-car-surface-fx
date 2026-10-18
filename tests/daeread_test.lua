-- carSurfaceFx/daeread.lua: the texture coordinate set that is asked for is the one that is read. (The set was taken from the first set="..." in the input, which is inside
-- offset="..." : with offset 2 every input looked like set 2, and set 1, the paint's, was never found.)
local dae = [[
<COLLADA><asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>
<library_materials><material id="paint-material" name="paint"/></library_materials>
<library_geometries><geometry id="g-mesh"><mesh>
<source id="pos"><float_array id="pa" count="9">0 0 0 1 0 0 0 1 0</float_array></source>
<source id="uv0"><float_array id="u0" count="6">0 0 1 0 0 1</float_array></source>
<source id="uv1"><float_array id="u1" count="6">0.5 0.5 0.6 0.5 0.5 0.6</float_array></source>
<vertices id="v"><input semantic="POSITION" source="#pos"/></vertices>
<triangles material="paint-material" count="1">
<input semantic="VERTEX" source="#v" offset="0"/>
<input semantic="NORMAL" source="#n" offset="1"/>
<input semantic="TEXCOORD" source="#uv0" offset="2" set="0"/>
<input semantic="TEXCOORD" source="#uv1" offset="2" set="1"/>
<p>0 0 0 1 0 1 2 0 2</p></triangles></mesh></geometry></library_geometries>
<library_visual_scenes><visual_scene><node id="n1" name="body"><instance_geometry url="#g-mesh"><bind_material><technique_common>
<instance_material symbol="paint-material" target="#paint-material"/></technique_common></bind_material></instance_geometry></node></visual_scene></library_visual_scenes></COLLADA>
]]
function readFile() return dae end
local read = require('carSurfaceFx/daeread').read
local function run(set)
  local tris = {}
  local co = coroutine.create(function() read('x.dae', { body = true }, { paint = true }, set, tris) end)
  while coroutine.status(co) ~= 'dead' do assert(coroutine.resume(co)) end
  return tris
end
local t1 = run(1)
assert(#t1 == 1 and math.abs(t1[1].uv[1] - 0.5) < 1e-9 and math.abs(t1[1].uv[4] - 0.5) < 1e-9, 'set 1 gives the second coordinates')
local t0 = run(0)
assert(#t0 == 1 and t0[1].uv[1] == 0 and t0[1].uv[3] == 1, 'set 0 gives the first')
local tn = run(nil)
assert(#tn == 1 and tn[1].uv[1] == 0, 'no set asked: the first')
print('carSurfaceFx daeread: ok')
