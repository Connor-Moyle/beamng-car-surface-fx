-- P16: the console debug set (carSurfaceFx_debug) and its car-side reporter, against mocks.
local saved = { vec3 = vec3, ColorF = ColorF, ColorI = ColorI, String = String, debugDrawer = rawget(_G, 'debugDrawer'), be = be, getAllVehicles = getAllVehicles, carSurfaceFx = rawget(_G, 'carSurfaceFx') }
for _, n in ipairs({ 'carSurfaceFx_marks', 'carSurfaceFx_fluids', 'carSurfaceFx_impacts', 'carSurfaceFx_ruts', 'carSurfaceFx_grass', 'carSurfaceFx_scratch' }) do saved[n] = rawget(_G, n) _G[n] = nil end

vec3 = function(x, y, z) local v = { x = x, y = y, z = z } return setmetatable(v, { __add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end }) end
ColorF = function() return {} end
ColorI = ColorF
String = function(s) return s end
local drawn = { spheres = 0, texts = {} }
debugDrawer = { drawSphere = function() drawn.spheres = drawn.spheres + 1 end, drawTextAdvanced = function(_, _, t) drawn.texts[#drawn.texts + 1] = t end }
local sent = {}
local veh = { getID = function() return 1 end, queueLuaCommand = function(_, c) sent[#sent + 1] = c end }
be = { getPlayerVehicleID = function() return 1 end }
getAllVehicles = function() return { veh } end
carSurfaceFx = { status = function() return 'main ok' end }

local D = dofile('mod/lua/ge/extensions/carSurfaceFx/debug.lua')
assert(D.counts() == 'no effect module is running' and D.help():find('counts'), 'nothing running, nothing to count')

local cleared = 0
carSurfaceFx_marks = { count = function(k) return k == 'skid' and 12 or 3 end, clear = function() cleared = cleared + 1 end }
carSurfaceFx_fluids = { count = function() return 4 end, clear = function() cleared = cleared + 1 end, status = function() return 'fluids ok' end }
carSurfaceFx_impacts = { status = function() return 'piles 2' end, clear = function() cleared = cleared + 1 end, test = function(w) cleared = cleared + 100 end }
carSurfaceFx_ruts = { status = function() return 'roads 5' end, clear = function() cleared = cleared + 1 end, test = function() cleared = cleared + 1000 end }
local c = D.counts()
assert(c:find('skid 12 track 3') and c:find('puddles: 4') and c:find('piles 2') and c:find('roads 5'), 'counts: ' .. c)
local s = D.status()
assert(s:find('main: main ok') and s:find('fluids: fluids ok') and s:find('ruts: roads 5'), 'status: ' .. s)
assert(D.clearAll() == 'cleared 4 modules' and cleared == 4, 'clear all')
cleared = 0
D.testAll()
assert(cleared == 1300, 'test all fires glass, debris, sparks and a rut: ' .. cleared)

-- the contacts and the labels
sent = {}
D.contacts(true)
assert(sent[1] and sent[1]:find('setOn%(true%)'), 'the car is told to report')
D.wheels(1, { { 0, 1, 2, 0.1, 'MUD', 'mud', 3500, 2.5 }, { 1, 3, 4, 0.1, 'ASPHALT', 'asphalt', 3000, 0 } })
D.onPreRender()
assert(drawn.spheres == 2 and #drawn.texts == 0, 'markers only')
D.surfaces(true)
D.onPreRender()
assert(#drawn.texts == 2 and drawn.texts[1]:find('mud %(MUD%) 3500 N slip 2.5'), 'labels: ' .. tostring(drawn.texts[1]))
D.contacts(false) D.surfaces(false)
drawn = { spheres = 0, texts = {} }
D.onPreRender()
assert(drawn.spheres == 0 and #drawn.texts == 0 and sent[#sent]:find('setOn%(false%)'), 'off draws nothing and tells the car')

-- the car side
local reported = {}
obj = { getAbsNodePosition = function(_, n) return { x = n, y = 0, z = 0.3 } end, getId = function() return 7 end, queueGameEngineLua = function(_, c) reported[#reported + 1] = c end }
wheels = { wheels = { [0] = { node1 = 1, node2 = 3, contactMaterialID1 = 4, contactMaterialID2 = 18, downForce = 3500, lastSlip = -2.5, radius = 0.3 } } }
particles = { getMaterialsParticlesTable = function() return { [18] = { name = 'MUD_WET' } } end }
local V = dofile('mod/lua/vehicle/extensions/carSurfaceFxDebug.lua')
V.updateGFX(1)
assert(#reported == 0, 'silent until switched on')
V.setOn(true)
V.updateGFX(0.1)
assert(#reported == 0, 'and at five times a second')
V.updateGFX(0.2)
assert(reported[1] and reported[1]:find('wheels%(7,{{0,2.00,0.00,0.00,"MUD_WET","mud",3500,2.50}}%)'), 'a wheel report: ' .. tostring(reported[1]))
V.setMaterials({ [18] = 'sand' })
V.updateGFX(0.3)
assert(reported[2]:find('"sand"'), 'a map-specific ground list wins')
obj, wheels, particles = nil, nil, nil

D.onExtensionUnloaded()
for _, n in ipairs({ 'carSurfaceFx_marks', 'carSurfaceFx_fluids', 'carSurfaceFx_impacts', 'carSurfaceFx_ruts', 'carSurfaceFx_grass', 'carSurfaceFx_scratch' }) do _G[n] = saved[n] end
vec3, ColorF, ColorI, String, debugDrawer, be, getAllVehicles, carSurfaceFx = saved.vec3, saved.ColorF, saved.ColorI, saved.String, saved.debugDrawer, saved.be, saved.getAllVehicles, saved.carSurfaceFx
print('carSurfaceFx debug tools: ok')
