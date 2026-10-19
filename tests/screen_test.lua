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
-- a frame from the car's own nodes: the camera's offset in it is learned at rest and rebuilt from the car's nodes at speed, whatever way the car has turned
local function frame(o, yaw)
  local c, s_ = math.cos(yaw), math.sin(yaw)
  return S.makeFrame(o, { x = o.x + c, y = o.y + s_, z = o.z }, { x = o.x - s_, y = o.y + c, z = o.z }, { x = o.x, y = o.y, z = o.z + 1 })
end
local st = {}
local c1 = { x = 10.3, y = 5, z = 1.2 }
assert(S.stabilise(st, c1, frame({ x = 10, y = 5, z = 0.5 }, 0), 0) == 0, 'at rest nothing is corrected')
assert(math.abs(st.off.x - 0.3) < 1e-9 and math.abs(st.off.y) < 1e-9 and math.abs(st.off.z - 0.7) < 1e-9, 'the eye offset is learned in the car frame')
local c2 = { x = 25.0, y = 5, z = 1.2 }                      -- the camera is a frame behind: the car is already at x = 25.4
local fix = S.stabilise(st, c2, frame({ x = 25.4, y = 5, z = 0.5 }, 0), 20)
assert(math.abs(c2.x - 25.7) < 1e-9 and math.abs(fix - 0.7) < 1e-9, 'at speed the camera is rebuilt from the car: ' .. c2.x .. ' ' .. fix)
local c3 = { x = 0, y = 0, z = 0 }                           -- the car turned 90 degrees: the offset turns with it
S.stabilise(st, c3, frame({ x = 100, y = 100, z = 0.5 }, math.pi / 2), 20)
assert(math.abs(c3.x - 100) < 1e-9 and math.abs(c3.y - 100.3) < 1e-9 and math.abs(c3.z - 1.2) < 1e-9, 'the offset turns with the car: ' .. c3.x .. ' ' .. c3.y)
-- never seen standing: the first offset allows for one frame of lag
local st2 = {}
local c4 = { x = 25.0, y = 5, z = 1.2 }
S.stabilise(st2, c4, frame({ x = 25.4, y = 5, z = 0.5 }, 0), 24, { x = 24, y = 0, z = 0 })
assert(math.abs(st2.off.x - (25.0 + 24 / 60 - 25.4)) < 1e-9, 'the default offset allows for the lag: ' .. st2.off.x)

-- the glass plane: nodes of the windscreen group that sit on a slanted plane are kept, the ones on the roof edge and the cowl are dropped
local pts = {}
for i = 0, 5 do for j = 0, 3 do pts[#pts + 1] = { x = -0.6 + i * 0.24, y = 0.2 + j * 0.15, z = 1.0 + (0.2 + j * 0.15) * 1.3 } end end   -- 24 nodes on the glass
pts[#pts + 1] = { x = -0.7, y = 0.5, z = 1.9 }                                -- a roof edge node, off the plane
pts[#pts + 1] = { x = 0.7, y = 0.1, z = 1.0 }                                 -- a cowl node
local keep = S.planeInliers(pts)
assert(#keep == 24, 'the 24 glass nodes are kept, the two others dropped: ' .. #keep)
local flat = {}
for i = 1, 5 do flat[i] = { x = i, y = i * i % 3, z = 0 } end
assert(#S.planeInliers(flat) == 5, 'nodes that all lie on one plane are all kept')
-- the outline clipped to the screen: inside stays, a part outside is cut at the edge, outside altogether is nothing
local function box(poly) local x0, y0, x1, y1 = 9, 9, -9, -9 for _, p in ipairs(poly) do x0, x1, y0, y1 = math.min(x0, p.x), math.max(x1, p.x), math.min(y0, p.y), math.max(y1, p.y) end return x0, y0, x1, y1 end
local inside = { { x = 0.2, y = 0.3 }, { x = 0.8, y = 0.3 }, { x = 0.8, y = 0.6 }, { x = 0.2, y = 0.6 } }
local same = S.clipHull(inside, 0, 0, 1, 1)
assert(#same == 4 and select(1, box(same)) == 0.2 and select(4, box(same)) == 0.6, 'a polygon inside the screen is left as it is')
local wide = { { x = -0.5, y = 0.4 }, { x = 2.1, y = 0.4 }, { x = 2.1, y = 1.3 }, { x = -0.5, y = 1.3 } }       -- like the drive trace: past the right edge and below the middle
local cx0, cy0, cx1, cy1 = box(S.clipHull(wide, 0, 0, 1, 1))
assert(cx0 == 0 and cx1 == 1 and cy0 == 0.4 and cy1 == 1, 'a polygon running off the screen is cut at its edges')
local tri = { { x = 0.5, y = 0.5 }, { x = 3, y = 0.5 }, { x = 0.5, y = 3 } }
local ct = S.clipHull(tri, 0, 0, 1, 1)
assert(#ct >= 4 and select(3, box(ct)) == 1 and select(4, box(ct)) == 1, 'a triangle clipped by two edges gains corners')
assert(S.clipHull({ { x = 2, y = 2 }, { x = 3, y = 2 }, { x = 3, y = 3 } }, 0, 0, 1, 1) == nil, 'outside altogether: nothing')
assert(S.clipHull({ { x = -1, y = 0.2 }, { x = 0, y = 0.2 }, { x = 0, y = 0.8 } }, 0, 0, 1, 1) == nil, 'touching the edge only: nothing')
assert(S.clipHull(nil, 0, 0, 1, 1) == nil, 'no polygon, no result')
-- the glass of a flexbody that covers more than the windscreen: only the nodes ahead of the eye
local near = S.eyeNodes({ { r = 0, u = -0.1, d = 0.6 }, { r = 0.5, u = -0.1, d = 0.6 }, { r = 0, u = 0.2, d = 0.8 }, { r = -0.5, u = 0.2, d = 0.8 }, { r = 0, u = -0.9, d = 0.5 }, { r = 0, u = 0, d = -0.4 }, { r = 0, u = -0.3, d = 2.0 } })
assert(near and #near == 4 and near[4] == 4, 'the hood, the nose and what is behind the eye are not the glass')
assert(S.eyeNodes({ { r = 0, u = 0, d = 0.5 }, { r = 0, u = 0, d = 0.6 } }) == nil, 'fewer than four: the old nodes are used')
print('carSurfaceFx screen: ok')
do local h = S.inset({ 0.2, 0.1, 0.8, 0.1, 0.8, 0.6, 0.2, 0.6 }, 0.9, 0.5)
  assert(math.abs(h[2] - 0.35) < 1e-9 and math.abs(h[6] - 0.6) < 1e-9 and math.abs(h[1] - 0.23) < 1e-9, 'the hull shrinks up from its bottom edge and in from its sides')
end
