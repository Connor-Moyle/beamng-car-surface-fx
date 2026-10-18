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
-- the eye stays where it is in the car's frame: learned at rest, rebuilt from the car's own position at speed
local q0 = { x = 0, y = 0, z = 0, w = 1 }
local st = {}
local c1 = { x = 10.3, y = 5, z = 1.2 }
assert(S.stabilise(st, c1, { x = 10, y = 5, z = 0.5 }, q0, 0) == 0, 'at rest nothing is corrected')
assert(math.abs(st.off.x - 0.3) < 1e-9 and math.abs(st.off.z - 0.7) < 1e-9, 'the eye offset is learned')
local c2 = { x = 25.0, y = 5, z = 1.2 }
local fix = S.stabilise(st, c2, { x = 25.4, y = 5, z = 0.5 }, q0, 20)
assert(math.abs(c2.x - 25.7) < 1e-9 and math.abs(fix - 0.7) < 1e-9, 'at speed the camera is rebuilt from the car: ' .. c2.x .. ' ' .. fix)
local q90 = { x = 0, y = 0, z = math.sqrt(0.5), w = math.sqrt(0.5) }
local c3 = { x = 0, y = 0, z = 0 }
S.stabilise(st, c3, { x = 100, y = 100, z = 0.5 }, q90, 20)
assert(math.abs(c3.x - 100) < 1e-6 and math.abs(c3.y - 100.3) < 1e-6 and math.abs(c3.z - 1.2) < 1e-9, 'the offset turns with the car: ' .. c3.x .. ' ' .. c3.y)
-- never seen standing: the first offset allows for one frame of lag
local st2 = {}
local c4 = { x = 25.0, y = 5, z = 1.2 }
S.stabilise(st2, c4, { x = 25.4, y = 5, z = 0.5 }, q0, 24, { x = 24, y = 0, z = 0 })
assert(math.abs(st2.off.x - (25.0 + 24 / 60 - 25.4)) < 1e-9, 'the default offset allows for the lag: ' .. st2.off.x)
print('carSurfaceFx screen: ok')
