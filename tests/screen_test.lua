-- The windscreen's outline on the screen (carSurfaceFx/screen.lua): hull, projection, mesh names.
local S = require('carSurfaceFx/screen')

-- hull of a square with points inside it and on its edges
local pts = { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 }, { x = 0, y = 1 }, { x = 0.5, y = 0.5 }, { x = 0.5, y = 0 }, { x = 0.2, y = 0.9 } }
local h = S.convexHull(pts)
assert(#h == 4, 'the four corners: ' .. tostring(h and #h))
assert(S.convexHull({ { x = 0, y = 0 }, { x = 1, y = 1 } }) == nil, 'two points are no outline')
assert(S.convexHull({ { x = 0, y = 0 }, { x = 1, y = 1 }, { x = 2, y = 2 } }) == nil, 'a line is no outline')

-- projection through a camera at the origin looking along +y (forward), x right, z up, 90 degrees across the height (halfTan 1), square screen
local cam = { x = 0, y = 0, z = 0, r = { x = 1, y = 0, z = 0 }, f = { x = 0, y = 1, z = 0 }, u = { x = 0, y = 0, z = 1 }, halfTan = 1, aspect = 1 }
local c = S.project({ x = 0, y = 5, z = 0 }, cam)
assert(math.abs(c.x - 0.5) < 1e-9 and math.abs(c.y - 0.5) < 1e-9, 'straight ahead is the middle')
local tr = S.project({ x = 5, y = 5, z = 5 }, cam)
assert(math.abs(tr.x - 1) < 1e-9 and math.abs(tr.y - 0) < 1e-9, 'right and up is the top right corner')
assert(S.project({ x = 0, y = -5, z = 0 }, cam) == nil, 'behind the camera is nothing')
cam.aspect = 2
assert(math.abs(S.project({ x = 5, y = 5, z = 0 }, cam).x - 0.75) < 1e-9, 'a wider screen squeezes the sideways angle')

local flat = S.flat({ { x = 0.123456, y = 0.5 }, { x = 1, y = 0 }, { x = 0, y = 1 } })
assert(#flat == 6 and flat[1] == 0.1235, 'flat list, 4 decimals')

assert(S.isWindscreenMesh('vivace_windshield'), 'windshield')
assert(S.isWindscreenMesh('etk800_windscreen'), 'windscreen')
assert(not S.isWindscreenMesh('vivace_windshield_int'), 'the inside pane is not it')
assert(not S.isWindscreenMesh('vivace_windshield_dmg'), 'nor the broken one')
assert(not S.isWindscreenMesh('vivace_sideglass_FL'), 'a side window')
print('carSurfaceFx screen: ok')
