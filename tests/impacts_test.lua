-- Crash effects: the rules (impactrules.lua), the GE module (impacts.lua) against a mocked game, the shared contact wrapper and the car side that uses it.
local R = require('carSurfaceFx/impactrules')
local cfg = R.defaults()

-- ---- the rules
assert(R.isGlassBeam({ deformGroup = 'a', breakGroup = 'b' }, 2, 2) and R.isGlassBeam({ deformGroup = 'a', breakGroup = 'b' }, 5, 2), 'a window: both groups, metal or glass nodes')
assert(not R.isGlassBeam({ deformGroup = 'a', breakGroup = 'b' }, 3, 3) and not R.isGlassBeam({ deformGroup = 'a', breakGroup = 'b' }, 6, 2), 'plastic lenses and wood are not windows')
assert(not R.isGlassBeam({ deformGroup = 'a' }, 2, 2) and not R.isGlassBeam(nil, 2, 2), 'a beam without both groups is not a window')

local cl = {}
for i = 1, 30 do R.addBreak(cl, 1 + i * 0.01, 2, 1, 10 + i * 0.01, 0.8, 12) end
assert(#cl == 1 and cl[1].n == 30, 'the breaks of one pane fold into one cluster: ' .. #cl .. ' ' .. cl[1].n)
R.addBreak(cl, 5, 5, 1, 10.5, 0.8, 12)
assert(#cl == 2, 'a break elsewhere is another pane')
assert(#R.flush(cl, 10.4, 0.22) == 0, 'a pane still breaking is not flushed')
local out = R.flush(cl, 11, 0.22)
assert(#out == 2 and out[1].sev == 1 and out[2].sev < 0.5 and #cl == 0, 'quiet panes flush, bigger break = bigger severity')
assert(R.pileRadius(1, 1) > R.pileRadius(0.3, 1) and R.pileRadius(1, 2) == 2 * R.pileRadius(1, 1), 'a bigger pane makes a bigger pile')

assert(R.classify(4, 2, 0.5) == nil, 'a tyre leaves nothing')
assert(R.classify(5, 2, 0.5) == 'glass' and R.classify(6, 2, 0.5) == 'wood' and R.classify(13, 2, 0.5) == 'rock' and R.classify(3, 2, 0.5) == 'plastic', 'materials make their pieces')
assert(R.classify(2, 2, 0.1, 0.3) == 'bolt' and R.classify(2, 2, 0.9, 0.3) == 'metal', 'metal is a chunk or a bolt')
assert(R.pieces('glass', true, cfg.debris) > R.pieces('metal', true, cfg.debris) and R.pieces('metal', true, cfg.debris) > R.pieces('metal', false, cfg.debris), 'glass throws more than a hit, a hit more than a joint')
assert(R.pieces('metal', true, { amount = 0 }) == 0, 'amount 0 throws nothing')

local p = { x = 0, y = 0, z = 2, vx = 3, vy = 0, vz = 1 }
local steps, rest = 0, false
while not rest and steps < 2000 do rest = R.step(p, 0.02, 0, 0.35, 0.55) steps = steps + 1 end
assert(rest and p.z == 0 and p.x > 0.5 and steps < 600, 'a piece falls, bounces, slides and comes to rest: ' .. steps .. ' ' .. p.x)

assert(R.sparkOk(2, 2, 2000, 5, cfg.sparks), 'metal grinding on metal sparks')
assert(not R.sparkOk(2, 14, 2000, 5, cfg.sparks) and not R.sparkOk(2, 4, 2000, 5, cfg.sparks) and not R.sparkOk(3, 3, 2000, 5, cfg.sparks), 'not on dirt, rubber or plastic')
assert(not R.sparkOk(2, 2, 100, 5, cfg.sparks) and not R.sparkOk(2, 2, 2000, 0.5, cfg.sparks), 'a feather touch or a slow slide does not spark')
assert(R.sparkCount(6000, cfg.sparks) > R.sparkCount(600, cfg.sparks), 'a harder scrape throws more sparks')
assert(R.SPARK_PARTICLE == 1 and R.particleFor('plastic', 0) == 56 and R.particleFor('plastic', 0.99) == 58 and R.particleFor('glass', 0.7) == 69 and R.particleFor('wood', 0.3) == 12, 'the game\'s own particle emitters by kind')

-- ---- the GE module against a mocked game
local saved = { vec3 = vec3, ColorF = ColorF, Engine = Engine, be = be, core_camera = core_camera, castRayStatic = castRayStatic, getAllVehicles = getAllVehicles, jsonReadFile = jsonReadFile,
  jsonWriteFile = jsonWriteFile, debugDrawer = debugDrawer, carSurfaceFx_marks = rawget(_G, 'carSurfaceFx_marks') }
local function V(x, y, z) local v = { x = x, y = y, z = z } function v:set(a, b, c) self.x, self.y, self.z = a, b, c end return v end
vec3 = V
ColorF = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
local batches = {}
Engine = { Render = { DynamicDecalMgr = { addDecals = function(pool, n2) batches[#batches + 1] = { n = n2, tex = pool[1].texture } end } } }
local sent = {}
local pv = { getID = function() return 1 end, getPosition = function() return { x = 0, y = 0, z = 0 } end, getDirectionVector = function() return { x = 1, y = 0, z = 0 } end,
  queueLuaCommand = function(_, cmd) sent[#sent + 1] = cmd end }
be = { getPlayerVehicleID = function() return 1 end, getObjectByID = function() return pv end, getObjectCount = function() return 1 end, getObject = function() return pv end,
  getPlayerVehicle = function() return pv end }
getAllVehicles = function() return { pv } end
core_camera = { getPosition = function() return { x = 0, y = 0, z = 0 } end }
castRayStatic = function() return 1.0 end                          -- the ground is 0.2 m below the point + 0.8
local files = {}
jsonReadFile = function(f) return files[f] end
jsonWriteFile = function(f, t) files[f] = t end
_G.carSurfaceFx_marks = nil

local I = dofile('mod/lua/ge/extensions/carSurfaceFx/impacts.lua')
I.onExtensionLoaded()
assert(I.get('glass.size') == 1 and I.get('nothing.here') == nil, 'settings by path')
assert(I.set('sparks.amount', 2) and not I.set('sparks.amount', 'lots'), 'a setting takes its own type only')
I.set('sparks.amount', 1)
assert(sent[#sent] and sent[#sent]:find('setConfig%(true, true, true'), 'the cars are told what to report: ' .. tostring(sent[#sent]))

I.glass(1, 5, 5, 1, 1) I.glass(1, 8, 5, 1, 0.4)
assert(I.pileCount() == 2, 'two glass piles')
I.onPreRender(0.016)
assert(#batches >= 1 and batches[1].tex:find('shards'), 'piles are drawn as decals')
batches = {}
core_camera.getPosition = function() return { x = 3000, y = 0, z = 0 } end
I.onPreRender(0.016)
assert(#batches == 0, 'far from the camera nothing is drawn')
core_camera.getPosition = function() return { x = 0, y = 0, z = 0 } end
for i = 1, 300 do I.glass(1, i, 0, 1, 0.5) end
assert(I.pileCount() == I.get('glass.maxPiles'), 'the piles are a ring')

I.debris(1, 2, 2, 1, 3, 0, 1, 'plastic', true, 0.15)
assert(I.flyingCount() >= 1, 'a hard hit throws pieces')
for _ = 1, 400 do I.onUpdate(0.02) end
assert(I.flyingCount() == 0 and I.restingCount() >= 1, 'the pieces settle on the road: ' .. I.status())
batches = {}
I.onPreRender(0.016)
local sawChip = false
for _, b in ipairs(batches) do if b.tex:find('chip') then sawChip = true end end
assert(sawChip, 'settled pieces are decals')
I.set('debris.life', 20)
for _ = 1, 25 do I.onUpdate(1) end
assert(I.restingCount() == 0, 'pieces are cleaned up after a while')
I.set('debris.life', 180)
I.debris(1, 2, 2, 1, 0, 0, 0, 'metal', true, 0.1)
for _ = 1, 400 do I.onUpdate(0.02) end
core_camera.getPosition = function() return { x = 5000, y = 0, z = 0 } end
I.onUpdate(1)
assert(I.restingCount() == 0, 'and when the camera has gone far away')
core_camera.getPosition = function() return { x = 0, y = 0, z = 0 } end
for _ = 1, 200 do I.debris(1, 2, 2, 1, 0, 0, 0, 'glass', true, 0.1) end
assert(I.flyingCount() <= I.get('debris.maxFlying'), 'at most maxFlying pieces in the air')
I.clear()

I.sparks()
assert(I.callCount('sparks') == 1, 'the GE side counts the spark calls (the sparks themselves are the game\'s particles on the car)')

-- the marks seam when the marks module is there
local seam = 0
_G.carSurfaceFx_marks = { drawBatch = function() seam = seam + 1 end }
I.glass(1, 5, 5, 1, 1)
batches = {}
I.onPreRender(0.016)
assert(seam >= 1 and #batches == 0, 'decals go through marks.drawBatch (the lighting seam)')
_G.carSurfaceFx_marks = nil
I.onExtensionUnloaded()

-- ---- the shared contact wrapper and the car side
local calls = {}
onNodeCollision = function(...) calls[#calls + 1] = 'orig' end
local particles = {}
obj = { addParticleVelWidthTypeCount = function(_, node, dir, vel, speed, width, ptype, count) particles[#particles + 1] = { node = node, ptype = ptype, count = count } end,
  getAbsNodePosition = function() return { x = 1, y = 2, z = 3 } end, getPosition = function() return { x = 0, y = 0, z = 0 } end, getNodeVelocityVector = function() return { x = 1, y = 0, z = 0 } end,
  getId = function() return 7 end, queueGameEngineLua = function(_, cmd) calls[#calls + 1] = cmd end, breakBeam = function(_, cid) calls[#calls + 1] = 'break' .. cid end }
wheels = { wheels = { [0] = { node1 = 100, node2 = 101 } } }
v = { data = { nodes = { [1] = { nodeMaterial = 2 }, [2] = { nodeMaterial = 2 }, [3] = { nodeMaterial = 3 }, [4] = { nodeMaterial = 3 } },
  beams = { [10] = { id1 = 1, id2 = 2, deformGroup = 'g', breakGroup = 'b', cid = 10 }, [11] = { id1 = 3, id2 = 4, deformGroup = 'g', breakGroup = 'b', cid = 11 }, [12] = { id1 = 1, id2 = 2, cid = 12 } } } }
extensions = { load = function(name) end }
local C = dofile('mod/lua/vehicle/extensions/carSurfaceFxContact.lua')
carSurfaceFxContact = C
C.onExtensionLoaded()
local got = {}
C.subscribe('t', function(ev) got[#got + 1] = { kind = ev.kind, node = ev.node, force = ev.normalForce, slip = ev.slip, beam = ev.beam, x = ev.x } end)
C.subscribe('bad', function() error('boom') end)
onNodeCollision(5, nil, nil, { x = 0, y = 0, z = 0 }, 7, nil, 4, 0, 2500, 0, 2, 2)
assert(calls[1] == 'orig' and #got == 0, 'inactive: the previous handler runs, no event')
C.setActive(true)
onNodeCollision(5, nil, nil, { x = 0, y = 0, z = 0 }, 7, nil, 4, 0, 2500, 0, 2, 2)
assert(#got == 1 and got[1].kind == 'node' and got[1].node == 5 and got[1].force == 2500 and got[1].slip == 4 and got[1].x == 1, 'a node collision reaches the subscribers, a failing one is isolated')
C.onBeamBroke(10, 50)
assert(#got == 2 and got[2].kind == 'beam' and got[2].beam == 10, 'a beam break too')
assert(C.isWheelNode(100) and not C.isWheelNode(5), 'wheel nodes are known')
C.unsubscribe('t')
C.onBeamBroke(10, 50)
assert(#got == 2, 'unsubscribed')

calls = {}
C.unsubscribe('bad')
dofile('mod/lua/vehicle/extensions/carSurfaceFxImpacts.lua')
local X = dofile('mod/lua/vehicle/extensions/carSurfaceFxImpacts.lua')
X.setConfig(true, true, true)
local function geCalls(pattern) local n2 = 0 for _, c in ipairs(calls) do if type(c) == 'string' and c:find(pattern) then n2 = n2 + 1 end end return n2 end
for i = 1, 25 do C.onBeamBroke(10, 50) end                            -- a window: many beams of one pane
assert(geCalls('impacts.glass') == 0, 'a pane still breaking is not reported yet')
for _ = 1, 20 do X.updateGFX(0.05) end
assert(geCalls('impacts.glass') == 1, 'one pile for the whole pane: ' .. geCalls('impacts.glass'))
calls = {}
math.randomseed(3)
for _ = 1, 40 do C.onBeamBroke(11, 50) end                            -- a plastic lens is not glass
for _ = 1, 20 do X.updateGFX(0.05) end
assert(geCalls('impacts.glass') == 0, 'a headlight lens is not a window')
calls = {}
particles = {}
onNodeCollision(5, nil, nil, { x = 0, y = 0, z = 0 }, 1, nil, 5, 0, 3000, 0, 2, 2)
assert(geCalls('impacts.sparks%(%)') == 1 and #particles == 1 and particles[1].ptype == 1 and particles[1].count >= 2, 'metal grinding on metal throws the game\'s own spark particle: ' .. #particles)
onNodeCollision(5, nil, nil, { x = 0, y = 0, z = 0 }, 1, nil, 5, 0, 3000, 0, 2, 14)
assert(#particles == 1, 'not on dirt (and the cooldown)')
calls = {}
for _ = 1, 3 do X.updateGFX(0.2) end
particles = {}
onNodeCollision(6, nil, nil, { x = 0, y = 0, z = 0 }, 12, nil, 0, 0, 100, 0, 3, 2)
assert(geCalls('impacts.debris') == 1 and #particles == 1 and particles[1].ptype >= 56 and particles[1].ptype <= 58, 'a hard hit on plastic throws the game\'s plastic chunk particles: ' .. #particles)
onNodeCollision(100, nil, nil, { x = 0, y = 0, z = 0 }, 12, nil, 0, 0, 100, 0, 3, 2)
assert(geCalls('impacts.debris') == 1, 'a wheel node never does')
assert(X.breakWindows() == 1, 'the test break finds the one window beam')
local same = true
for kind, list in pairs(R.PARTICLE) do for i, id in ipairs(list) do if X.PARTICLE[kind][i] ~= id then same = false end end end
assert(same, 'the car side and the GE side use the same particle numbers')
X.test('sparks')
assert(#particles > 3, 'the test throws sparks by hand')

-- the tap through the game's own particlefilter.nodeCollision(p) (what main.lua calls for every collision): preferred when the module is there
do
  local order = {}
  particlefilter = { nodeCollision = function(p) order[#order + 1] = 'orig' end }
  onNodeCollision = nil
  local C2 = dofile('mod/lua/vehicle/extensions/carSurfaceFxContact.lua')
  C2.onExtensionLoaded()
  local ev2
  C2.subscribe('pf', function(ev) order[#order + 1] = 'sub' ev2 = { node = ev.node, perp = ev.perp, force = ev.normalForce, m1 = ev.mat1, m2 = ev.mat2, nodeMat = ev.nodeMat, hitMat = ev.hitMat } end)
  C2.setActive(true)
  particlefilter.nodeCollision({ id1 = 9, pos = nil, normal = nil, nodeVel = { x = 0, y = 0, z = 0 }, perpendicularVel = 3.5, slipVel = 1, normalForce = 4200, depth = 0, materialID1 = 2, materialID2 = 13 })
  assert(order[1] == 'orig' and order[2] == 'sub', 'the game handler runs first, then the subscriber')
  assert(ev2.node == 9 and ev2.perp == 3.5 and ev2.force == 4200 and ev2.m1 == 2 and ev2.m2 == 13, 'the numbers of the collision reach the subscriber')
  assert(C2.status():find('tap particlefilter', 1, true) and C2.status():find('collisions seen 1', 1, true) and C2.status():find('published 1', 1, true), 'the status line says which tap and how many')
  -- the node's own material decides which id is the car's and which the thing it touched
  v.data.nodes[9] = { nodeMaterial = 3 }
  particlefilter.nodeCollision({ id1 = 9, nodeVel = { x = 0, y = 0, z = 0 }, perpendicularVel = 2, normalForce = 1, materialID1 = 14, materialID2 = 3 })
  assert(ev2.nodeMat == 3 and ev2.hitMat == 14, 'the node is the plastic one (second id), it hit 14')
  particlefilter.nodeCollision({ id1 = 9, nodeVel = { x = 0, y = 0, z = 0 }, perpendicularVel = 2, normalForce = 1, materialID1 = 3, materialID2 = 10 })
  assert(ev2.nodeMat == 3 and ev2.hitMat == 10, 'the node is the plastic one (first id), it hit 10')
  v.data.nodes[9] = nil
  particlefilter.nodeCollision({ id1 = 9, nodeVel = { x = 0, y = 0, z = 0 }, perpendicularVel = 2, normalForce = 1, materialID1 = 10, materialID2 = 4 })
  assert(ev2.nodeMat == 4 and ev2.hitMat == 10, 'an unknown node: the second id is the node (asphalt, rubber = a tyre)')
  particlefilter = nil
end

-- restore
vec3, ColorF, Engine, be, core_camera, castRayStatic, getAllVehicles, jsonReadFile, jsonWriteFile, debugDrawer = saved.vec3, saved.ColorF, saved.Engine, saved.be, saved.core_camera,
  saved.castRayStatic, saved.getAllVehicles, saved.jsonReadFile, saved.jsonWriteFile, saved.debugDrawer
_G.carSurfaceFx_marks = saved.carSurfaceFx_marks
obj, wheels, v, extensions, onNodeCollision, carSurfaceFxContact, carSurfaceFxImpacts = nil, nil, nil, nil, nil, nil, nil
print('carSurfaceFx impacts: ok')
