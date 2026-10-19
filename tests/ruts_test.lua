-- P4 ruts: the rules (rutrules.lua), the GE module (ruts.lua) against a mocked game with DecalRoads and with the fallback, and the car side.
local R = require('carSurfaceFx/rutrules')
local cfg = R.defaults()

-- ---- the rules
local mud, dirt, gravel = R.depth('mud', 4000, 0, cfg), R.depth('dirt', 4000, 0, cfg), R.depth('gravel', 4000, 0, cfg)
assert(mud > dirt and dirt > gravel and mud == 1.0, 'softer ground, deeper rut: ' .. mud .. ' ' .. dirt .. ' ' .. gravel)
assert(R.depth('mud', 8000, 0, cfg) > R.depth('mud', 4000, 0, cfg) and R.depth('mud', 4000, 8, cfg) > mud, 'a heavier wheel and a spinning wheel press deeper')
assert(R.depth('tarmac', 4000, 0, cfg) == 0 and R.depth('lava', 4000, 0, cfg) == 0, 'hard ground and unknown ground take nothing')
assert(R.takes('mud', 4000, 0, cfg) and not R.takes('gravel', 1000, 0, cfg) and R.takes('gravel', 4000, 0, cfg), 'a light car on gravel leaves nothing, a normal one does')
cfg.kinds.mud.enabled = false
assert(R.depth('mud', 4000, 0, cfg) == 0, 'a ground can be switched off')
cfg.kinds.mud.enabled = true

assert(R.width(0.9, 1.2, 1, cfg) > R.width(0.9, 0.3, 1, cfg) and R.width(0.9, 1, 3, cfg) > R.width(0.9, 1, 1, cfg), 'wider with the load and with each pass')

-- passes: the same track deepens, up to maxLayers
local grid = R.newGrid()
local pts = { { 10, 10, 0 }, { 10.5, 10, 0 }, { 11, 10, 0 } }
assert(R.layerFor(grid, 'mud', pts, cfg) == 1, 'a fresh track is layer 1')
R.markPassed(grid, 'mud', pts)
assert(R.layerFor(grid, 'mud', pts, cfg) == 2 and R.layerFor(grid, 'sand', pts, cfg) == 1, 'the second pass is layer 2; another ground is its own')
R.markPassed(grid, 'mud', pts) R.markPassed(grid, 'mud', pts)
assert(R.layerFor(grid, 'mud', pts, cfg) == 4 and R.layerFor(grid, 'mud', pts, cfg) > cfg.maxLayers, 'past maxLayers a track is as deep as it gets')
assert(R.layerFor(grid, 'mud', { { 40, 40, 0 } }, cfg) == 1, 'a track beside is fresh')

-- paths: samples cut into chunks, the next starts where the last ended, the ground changes and jumps cut
local path = R.newPath()
local chunks = {}
for i = 0, 10 do local c = R.feed(path, i * 0.6, 0, 0, 'mud', cfg) if c then chunks[#chunks + 1] = c end end
assert(#chunks == 2 and #chunks[1].points == cfg.chunkPoints and chunks[2].points[1][1] == chunks[1].points[cfg.chunkPoints][1], 'chunks of chunkPoints samples that join: ' .. #chunks)
local c2 = R.feed(path, 7.6, 0, 0, 'sand', cfg)
assert(c2 and c2.kind == 'mud', 'the ground changed: the mud chunk ends')
local path2 = R.newPath()
R.feed(path2, 0, 0, 0, 'mud', cfg) R.feed(path2, 0.6, 0, 0, 'mud', cfg)
local jump = R.feed(path2, 50, 0, 0, 'mud', cfg)
assert(jump and #jump.points == 2, 'a jump of metres cuts the path')
assert(R.feed(R.newPath(), 0, 0, 0, 'mud', cfg) == nil, 'one sample is no chunk')
local path3 = R.newPath()
R.feed(path3, 0, 0, 0, 'dirt', cfg) R.feed(path3, 0.6, 0, 0, 'dirt', cfg)
assert(R.flush(path3) and R.flush(path3) == nil, 'a quiet path flushes once')
local same = R.newPath()
R.feed(same, 0, 0, 0, 'mud', cfg)
R.feed(same, 0.1, 0, 0, 'mud', cfg)
assert(#same.points == 1, 'samples closer than a step are ignored')

-- the material: wet or dry with hysteresis
local m, wasWet = R.material('mud', 0.1, false, cfg)
assert(m == 'csfx_rut_mud_dry' and not wasWet, 'dry')
m, wasWet = R.material('mud', 0.5, wasWet, cfg)
assert(m == 'csfx_rut_mud_wet' and wasWet, 'wet above the threshold')
m, wasWet = R.material('mud', 0.25, wasWet, cfg)
assert(m == 'csfx_rut_mud_wet' and wasWet, 'and stays wet until clearly drier')
m, wasWet = R.material('mud', 0.1, wasWet, cfg)
assert(m == 'csfx_rut_mud_dry' and not wasWet, 'dry again')

local b = {}
local got = 0
for _ = 1, 20 do if R.budget(b, 0, 6) then got = got + 1 end end
assert(got == 6, 'a bucket of six: ' .. got)

-- the module's loop: 120 frames at 60 fps with 24 chunks waiting and 6 a second drains steadily (about 12 in two seconds), also after a long quiet spell
local bk = {}
for _ = 1, 600 do R.refill(bk, 0.016, 6) end                         -- ten quiet seconds
local waiting, made2 = 24, 0
for _ = 1, 120 do
  while waiting > 0 and R.budget(bk, 0, 6) do waiting = waiting - 1 made2 = made2 + 1 end
  R.refill(bk, 0.016, 6)
end
assert(made2 >= 12 and made2 <= 19, 'steady draining, not a burst and then nothing: ' .. made2)
assert(R.budget(b, 0.5, 6) and R.budget(b, 0, 6) and R.budget(b, 0, 6) and not R.budget(b, 0, 6), 'and it refills over time: three after half a second')

-- ---- the GE module against a mocked game
local saved = { vec3 = vec3, ColorF = ColorF, Engine = Engine, be = be, core_camera = core_camera, castRayStatic = castRayStatic, getAllVehicles = getAllVehicles, jsonReadFile = jsonReadFile,
  jsonWriteFile = jsonWriteFile, createObject = createObject, scenetree = scenetree, log = log, carSurfaceFx = rawget(_G, 'carSurfaceFx'), marksMod = package.loaded['carSurfaceFx/markMaterials'],
  carSurfaceFx_marks = rawget(_G, 'carSurfaceFx_marks') }
vec3 = function(x, y, z) local v = { x = x, y = y, z = z } function v:set(a, b2, c) self.x, self.y, self.z = a, b2, c end return v end
ColorF = function(r, g, b2, a) return { r = r, g = g, b = b2, a = a } end
local decals = {}
Engine = { Render = { DynamicDecalMgr = { addDecals = function(pool, n) decals[#decals + 1] = { n = n, tex = pool[1].texture } end } } }
local sent = {}
local pv = { getID = function() return 1 end, getPosition = function() return { x = 0, y = 0, z = 0 } end, getDirectionVector = function() return { x = 1, y = 0, z = 0 } end,
  queueLuaCommand = function(_, cmd) sent[#sent + 1] = cmd end }
be = { getPlayerVehicleID = function() return 1 end, getObjectByID = function() return pv end, getObjectCount = function() return 1 end, getObject = function() return pv end, getPlayerVehicle = function() return pv end }
getAllVehicles = function() return { pv } end
core_camera = { getPosition = function() return { x = 0, y = 0, z = 0 } end }
castRayStatic = function() return 1.0 end
local files = {}
jsonReadFile = function(f) return files[f] end
jsonWriteFile = function(f, t) files[f] = t end
local logs = {}
log = function(level, tag, text) logs[#logs + 1] = level .. ' ' .. tostring(text) end
_G.carSurfaceFx_marks = nil
local wetValue = 0
_G.carSurfaceFx = { wetness = function() return wetValue end }
package.loaded['carSurfaceFx/markMaterials'] = { index = function() return { { type = 'rut_mud', width = 0.9, textureLength = 4 } } end, ensure = function() return true end }

local objects, nextId, canMake = {}, 100, true
local function newRoad()
  nextId = nextId + 1
  local r = { id = nextId, fields = {}, nodes = {} }
  function r:setField(k, _, v) self.fields[k] = v end
  function r:registerObject() end
  function r:insertNode(p, w, i) self.nodes[#self.nodes + 1] = { w = w, i = i } end
  function r:getID() return self.id end
  function r:deleteObject() objects[self.id] = nil end
  objects[r.id] = r
  return r
end
createObject = function(class) if class == 'DecalRoad' and canMake then return newRoad() end return nil end
scenetree = { MissionGroup = { add = function() end }, findObjectById = function(id) return objects[id] end }

local U = dofile('mod/lua/ge/extensions/carSurfaceFx/ruts.lua')
U.onExtensionLoaded()
assert(U.get('widthScale') == 1 and U.get('nothing') == nil and U.set('widthScale', 1.5) and not U.set('widthScale', 'wide'), 'settings by path')
U.set('widthScale', 1) U.set('enabled', true)
assert(sent[#sent] and sent[#sent]:find('setConfig%(true'), 'the car is told to report')

-- a heavy car driving through mud: samples every 0.6 m
local function drive(from, n, kind, load)
  for i = 0, n do U.sample(1, 0, from + i * 0.6, 5, 0, kind or 'mud', load or 4000, 0) end
end
drive(0, 14)
U.onUpdate(0.2)
assert(U.roadCount() >= 2 and U.mode() == 'road', 'chunks become DecalRoads: ' .. U.status())
local first = objects[101]
assert(first and first.fields.material == 'csfx_rut_mud_dry' and #first.nodes == 5 and first.fields.textureLength == '4', 'a road with the dry mud rut material and the chunk\'s nodes')
-- the wet material when it rains
wetValue = 0.8
drive(30, 5)
U.onUpdate(0.5)
local wetOne
for _, o in pairs(objects) do if o.fields.material == 'csfx_rut_mud_wet' then wetOne = o end end
assert(wetOne, 'ruts made in the wet use the wet material')
wetValue = 0
-- the same track again deepens it: layer 2 (a new road over it, a bit wider)
local before = U.roadCount()
drive(0, 14)
U.onUpdate(0.5)
assert(U.roadCount() > before, 'a second pass adds a layer: ' .. before .. ' -> ' .. U.roadCount())
local layers = 0
for _, o in pairs(objects) do if o.fields.renderPriority == 12 then layers = layers + 1 end end
assert(layers >= 1, 'the second pass is drawn over the first (render priority 12)')
for _ = 1, 3 do drive(0, 14) U.onUpdate(0.5) U.onUpdate(0.5) end
local deepest = U.roadCount()
drive(0, 14) U.onUpdate(0.5) U.onUpdate(0.5)
assert(U.roadCount() == deepest, 'past maxLayers a track is left alone')
-- a light wheel on gravel leaves nothing
local roadsNow = U.roadCount()
for i = 0, 12 do U.sample(1, 1, 60 + i * 0.6, 5, 0, 'gravel', 1000, 0) end
U.onUpdate(0.5)
assert(U.roadCount() == roadsNow, 'a light wheel on gravel leaves no rut')
-- gouges: a body panel dragged over the ground leaves a scrape (tarmac) or a furrow (soft ground) when its switch is on
do
  local mt = { __add = function(p, q) return setmetatable({ x = p.x + q.x, y = p.y + q.y, z = p.z + q.z }, getmetatable(p)) end }
  local oldPos, oldNode = pv.getPosition, pv.getNodePosition
  pv.getPosition = function() return setmetatable({ x = 0, y = 0, z = 0 }, mt) end
  local slide = 0
  pv.getNodePosition = function() return setmetatable({ x = 100 + slide, y = 0, z = 0.1 }, mt) end
  local oldSurf = package.loaded['carSurfaceFx/surfaces']
  package.loaded['carSurfaceFx/surfaces'] = { idTable = function() return { [7] = 'tarmac', [8] = 'dirt', [9] = 'ice' } end }
  local function slideOver(mat, force, n)
    for i = 1, n do slide = slide + 0.4 U.gouge(1, 5, mat, force) end
  end
  U.clear()
  local n0 = U.roadCount()
  slideOver(7, 3000, 12) U.onUpdate(0.5) U.onUpdate(0.5)
  assert(U.roadCount() == n0, 'gouges are off by default')
  U.set('gouges.enabled', true)
  slideOver(9, 3000, 12) U.onUpdate(0.5) U.onUpdate(0.5)
  assert(U.roadCount() == n0, 'ice takes no gouge')
  slideOver(7, 100, 12) U.onUpdate(0.5) U.onUpdate(0.5)
  assert(U.roadCount() == n0, 'a light touch leaves nothing')
  slideOver(7, 3000, 12) U.onUpdate(0.5) U.onUpdate(0.5)
  local tar
  for _, o in pairs(objects) do if o.fields.material == 'csfx_gouge_asphalt_dry' then tar = o end end
  assert(tar and #tar.nodes == 4 and tar.nodes[1].w >= 0.25 and tar.nodes[1].w <= 0.7, 'a scrape on tarmac: a gouge road of chunkPoints nodes, 0.25-0.7 m wide')
  slide = slide + 50
  slideOver(8, 6000, 12) U.onUpdate(0.5) U.onUpdate(0.5)
  local dirt
  for _, o in pairs(objects) do if o.fields.material == 'csfx_gouge_dirt_dry' then dirt = o end end
  assert(dirt and dirt.nodes[1].w > tar.nodes[1].w, 'a furrow in dirt, wider with a harder hit')
  wetValue = 0.8
  slide = slide + 50
  slideOver(7, 3000, 12) U.onUpdate(0.5) U.onUpdate(0.5)
  local wet
  for _, o in pairs(objects) do if o.fields.material == 'csfx_gouge_asphalt_wet' then wet = o end end
  assert(wet, 'in the rain the wet gouge material')
  wetValue = 0
  U.set('gouges.enabled', false)
  pv.getPosition, pv.getNodePosition = oldPos, oldNode
  package.loaded['carSurfaceFx/surfaces'] = oldSurf
  U.clear()
end

-- the budget
U.clear()
for k = 0, 9 do for i = 0, 6 do U.sample(1, 0, k * 20 + i * 0.6, 5, 0, 'mud', 4000, 0) end end
U.onUpdate(0.001)
assert(U.roadCount() <= 6 and U.pendingCount() >= 1, 'chunks are made within the budget, the rest wait: ' .. U.roadCount() .. ' ' .. U.pendingCount())
for _ = 1, 20 do U.onUpdate(0.5) end
assert(U.pendingCount() == 0, 'and are made later')
-- the ring
U.set('maxRoads', 20)
U.clear()
for k = 0, 40 do for i = 0, 6 do U.sample(1, 0, k * 30 + i * 0.6, 5, 0, 'mud', 4000, 0) end U.onUpdate(0.5) end
local alive = 0
for _ in pairs(objects) do alive = alive + 1 end
assert(U.roadCount() <= 20 and alive <= 20, 'the oldest road objects are removed: ' .. alive)

-- the fallback: a DecalRoad cannot be made once, one log line, ground decals instead
U.clear()
canMake = false
logs = {}
for i = 0, 10 do U.sample(1, 0, i * 0.6, 8, 0, 'mud', 4000, 0) end
U.onUpdate(0.5)
assert(U.mode() == 'decal' and U.segmentCount() >= 3 and #logs == 1 and logs[1]:find('ground decals'), 'fallback to ground decals, logged once: ' .. U.status() .. ' ' .. #logs)
for i = 0, 10 do U.sample(1, 0, 40 + i * 0.6, 8, 0, 'mud', 4000, 0) end
U.onUpdate(0.5)
assert(#logs == 1, 'and not logged again')
decals = {}
U.onPreRender(0.016)
assert(#decals == 1 and decals[1].tex:find('rut'), 'the fallback is drawn as ground decals')
local seam = 0
_G.carSurfaceFx_marks = { drawBatch = function() seam = seam + 1 end }
decals = {}
U.onPreRender(0.016)
assert(seam == 1 and #decals == 0, 'through marks.drawBatch when the marks module is there')
_G.carSurfaceFx_marks = nil
core_camera.getPosition = function() return { x = 5000, y = 0, z = 0 } end
decals = {}
U.onPreRender(0.016)
assert(#decals == 0, 'far from the camera nothing is drawn')
core_camera.getPosition = function() return { x = 0, y = 0, z = 0 } end

-- the routing setting by choice
canMake = true
U.clear()
U.reload()
U.set('routing', 'decal')
for i = 0, 10 do U.sample(1, 0, i * 0.6, 12, 0, 'snow', 4000, 0) end
U.onUpdate(0.5)
assert(U.mode() == 'decal' and U.roadCount() == 0 and U.segmentCount() >= 3, 'the decal route can be chosen')
U.onExtensionUnloaded()

-- ---- the car side
local samples = {}
obj = { getVelocity = function() return { x = 8, y = 0, z = 0 } end, getAbsNodePosition = function(_, n) return ({ [1] = { x = 1, y = 2, z = 0.3 }, [2] = { x = 1, y = 2, z = 0.3 }, [3] = { x = 5, y = 6, z = 0.3 }, [4] = { x = 5, y = 6, z = 0.3 } })[n] end,
  queueGameEngineLua = function(_, cmd) samples[#samples + 1] = cmd end, getId = function() return 7 end }
wheels = { wheels = { [0] = { node1 = 1, node2 = 2, downForce = 3500, contactMaterialID1 = 4, contactMaterialID2 = 18, lastSlip = 2.5, radius = 0.3 },
  [1] = { node1 = 3, node2 = 4, downForce = 3500, contactMaterialID1 = 4, contactMaterialID2 = 10 } } }
particles = { getMaterialsParticlesTable = function() return { [10] = { name = 'ASPHALT' }, [18] = { name = 'MUD' }, [15] = { name = 'DIRT' }, [22] = { name = 'SNOW' }, [20] = { name = 'GRASS' } } end }
local C = dofile('mod/lua/vehicle/extensions/carSurfaceFxRuts.lua')
C.setConfig(true, 0.6, 150)
C.updateGFX(0.1)
assert(#samples == 1 and samples[1]:find('sample%(7,0,1.00,2.00,0.00,"mud",3500,2.50%)') and not samples[1]:find('sample%(7,1,'), 'the loaded wheel on mud reports; the wheel on asphalt does not: ' .. tostring(samples[1]))
samples = {}
C.updateGFX(0.1)
assert(#samples == 0, 'no new sample before the wheel has moved a step')
C.setMaterials({ [10] = 'sand', [20] = 'mud', [44] = 'gravel' })
C.updateGFX(0.1) C.updateGFX(0.1)
assert(C.nameToKind('Sandy_ROAD') == 'sand' and C.nameToKind('DIRT_DUSTY') == 'dirt' and C.nameToKind('grass') == nil, 'the names')
C.setConfig(false)
samples = {}
wheels.wheels[0].node1, wheels.wheels[0].node2 = 9, 9
obj.getAbsNodePosition = function() return { x = 30, y = 30, z = 0 } end
C.updateGFX(0.1)
assert(#samples == 0, 'nothing when it is not asked to report')

-- restore
vec3, ColorF, Engine, be, core_camera, castRayStatic, getAllVehicles, jsonReadFile, jsonWriteFile, createObject, scenetree, log = saved.vec3, saved.ColorF, saved.Engine, saved.be, saved.core_camera,
  saved.castRayStatic, saved.getAllVehicles, saved.jsonReadFile, saved.jsonWriteFile, saved.createObject, saved.scenetree, saved.log
_G.carSurfaceFx, _G.carSurfaceFx_marks = saved.carSurfaceFx, saved.carSurfaceFx_marks
package.loaded['carSurfaceFx/markMaterials'] = saved.marksMod
obj, wheels, particles = nil, nil, nil
print('carSurfaceFx ruts: ok')
