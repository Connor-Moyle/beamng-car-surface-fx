-- Which way water runs on each window (carSurfaceFx/glassflow.lua): the flow of a triangle, the grid, and the whole path from a .dae text to the messages for the page.
local G = require('carSurfaceFx/glassflow')
local function close(a, b) return math.abs(a - b) < 1e-6 end

-- a windscreen slanted back 45 degrees: points (x left, y back, z up) = (x, y, y): rises toward the back. UV: u = x, v = 1 - y (the picture is turned: v runs down the glass as y falls)
local pos = { 0, 0, 0, 1, 0, 0, 0, 1, 1 }
local uv = { 0, 1, 1, 1, 0, 0 }
local f = G.triangleFlow(pos, uv)
assert(f, 'a triangle with an area has a flow')
-- down: the part of (0,0,-1) along the pane runs toward -y (and -z): in this UV that is +v... u unchanged
assert(close(f[1][1], 0) and f[1][2] > 0.6 and f[1][2] < 0.8, 'down runs along v on the slanted pane, with a slope of about 0.71: ' .. f[1][1] .. ' ' .. f[1][2])
assert(f[2][2] < -0.6, 'the airflow (back) runs the other way: up the glass')
assert(close(f[3][1], -1) and close(f[3][2], 0), 'right (-x) runs along -u, fully in the pane')

-- the same pane with its picture turned a quarter: u = 1 - y, v = x: down now runs along u
local f2 = G.triangleFlow(pos, { 0, 1 - 0 + 0, 1, 1, 0, 0 })
-- a flat roof pane: gravity has no slope
local flat = G.triangleFlow({ 0, 0, 1, 1, 0, 1, 0, 1, 1 }, { 0, 0, 1, 0, 0, 1 })
assert(close(flat[1][1], 0) and close(flat[1][2], 0), 'water does not run on a flat pane')
assert(G.triangleFlow({ 0, 0, 0, 1, 0, 0, 2, 0, 0 }, { 0, 0, 1, 0, 2, 0 }) == nil, 'a degenerate triangle has no flow')

-- the grid
-- the .dae's v runs up while the canvas runs down: the fixtures above are in canvas terms, so turn their v over for the field (it turns it back)
local function dv(u) return { u[1], 1 - u[2], u[3], 1 - u[4], u[5], 1 - u[6] } end
local tris = { { pos = pos, uv = dv(uv) }, { pos = { 0, 1, 1, 1, 0, 0, 1, 1, 1 }, uv = dv({ 0, 0, 1, 1, 1, 0 }) } }
local field = G.field(tris)
assert(field.filled > 100 and #field.g == G.N * G.N * 2, 'the cells under the triangles are filled: ' .. field.filled)
local c = (16 * G.N + 8) * 2                                      -- a cell inside the first triangle
assert(field.g[c + 2] > 0.5, 'the cell has the pane\'s down: ' .. tostring(field.g[c + 2]))

-- texture coordinates outside 0..1 wrap: the same pane drawn at u + 1.2, v - 0.8 fills cells all the same
local shifted = G.field({ { pos = pos, uv = dv({ uv[1] + 1.2, uv[2] - 0.8, uv[3] + 1.2, uv[4] - 0.8, uv[5] + 1.2, uv[6] - 0.8 }) } })
assert(shifted.filled > 100, 'a triangle whose coordinates lie outside the first tile is wrapped into it: ' .. shifted.filled)

-- the messages for the page: three kinds, in pieces of 256 numbers
local msgs = G.messages(field)
assert(#msgs == 3 * (G.N * G.N * 2 / 256) + G.N * G.N / 256, 'a message per 256 numbers and kind (three directions and the mask of glass cells): ' .. #msgs)
assert(field.m[16 * G.N + 8 + 1] == 1 and #field.m == G.N * G.N and field.uvPerM > 0, 'the mask marks the glass cells, and the texture density is known')
assert(msgs[1]:find('^csfxFlow%("g",0,%['), 'the first piece starts at 0')

-- from a .dae text: a car with one windshield flexbody whose triangle carries the glass material
local dae = [[<COLLADA><asset><unit meter="1"/><up_axis>Z_UP</up_axis></asset>
<library_materials><material id="glassid" name="car_glass"/></library_materials>
<library_geometries><geometry id="g1"><mesh>
<source id="pos"><float_array count="9">0 0 0 1 0 0 0 1 1</float_array></source>
<source id="uvs"><float_array count="6">0 0 1 0 0 1</float_array></source>
<vertices id="v"><input semantic="POSITION" source="#pos"/></vertices>
<triangles material="symG" count="1"><input semantic="VERTEX" source="#v" offset="0"/><input semantic="TEXCOORD" source="#uvs" offset="1" set="0"/><p>0 0 1 1 2 2</p></triangles>
</mesh></geometry></library_geometries>
<library_visual_scenes><visual_scene><node id="n" name="car_windshield"><matrix>1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1</matrix><instance_geometry url="#g1"><bind_material><technique_common><instance_material symbol="symG" target="#glassid"/></technique_common></bind_material></instance_geometry></node></visual_scene></library_visual_scenes></COLLADA>]]
function readFile() return dae end
FS = { findFiles = function() return { '/vehicles/car/car.dae' } end }
function log() end
function hptimer() return { stop = function() return 0 end } end
core_vehicle_manager = { getVehicleData = function() return { vehicleDirectory = '/vehicles/car/', vdata = { flexbodies = { { mesh = 'car_windshield' } } } } end }
local got
G.request(5, { car_glass = true }, function(f) got = f end)
for _ = 1, 20 do G.tick() if got then break end end
assert(got and got.car_glass and got.car_glass.filled > 0, 'the field was built from the mesh')
assert(got.car_glass.g[(16 * G.N + 8) * 2 + 2] > 0.5, 'and the windshield\'s down is along its v')
local again
G.request(5, { car_glass = true }, function(f) again = f end)
assert(again == got, 'a second request of the same car is the cached one')
-- the rear glass: a pane that faces along the car in the back of its length is marked 2 in the mask, a front one 1
do
  local front = { pos = { 0, 0, 0, 1, 0, 0, 0, 0, 1 }, uv = dv({ 0.1, 0.1, 0.3, 0.1, 0.1, 0.3 }) }          -- in the plane y = 0 (faces along y), at the front
  local back = { pos = { 0, 1, 0, 1, 1, 0, 0, 1, 1 }, uv = dv({ 0.6, 0.6, 0.9, 0.6, 0.6, 0.9 }) }              -- in the plane y = 1: the back
  local f2 = G.field({ front, back })
  assert(f2.m[(math.floor(0.85 * G.N) - 0) * G.N + math.floor(0.62 * G.N) + 1] == 2 or f2.m[math.floor((1 - 0.65) * G.N) * G.N + math.floor(0.65 * G.N) + 1] == 2, 'the pane at the back is rear glass')
  local rear, plain = 0, 0 for c = 1, G.N * G.N do if f2.m[c] == 2 then rear = rear + 1 elseif f2.m[c] == 1 then plain = plain + 1 end end
  assert(rear > 0 and plain > 0, 'one pane is rear glass and the other not: ' .. rear .. ' ' .. plain)
end
print('carSurfaceFx glass flow: ok')
