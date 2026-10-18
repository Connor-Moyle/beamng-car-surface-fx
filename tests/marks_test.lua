-- The ground marks (carSurfaceFx/marks.lua) against a mocked game: ring buffers, one batch per surface, the cull distance, takeover and its restore, settings and the old mod's file.
local drawn, batches, lastTex = 0, 0, nil
local function V(x, y, z) local v = { x = x, y = y, z = z } function v:set(a, b, c) self.x, self.y, self.z = a, b, c end return v end
vec3 = V
ColorF = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
Engine = { Render = { DynamicDecalMgr = { addDecals = function(pool, n) drawn, batches, lastTex = drawn + n, batches + 1, pool[1].texture end } } }
local cam = { x = 0, y = 0, z = 0 }
core_camera = { getPosition = function() return cam end }
local flags, setCalls = { ASPHALT = true, DIRT = true }, 0
local gms = {}
for name in pairs(flags) do gms[name] = { cdata = { skidMarks = true } } end
core_environment = { groundModels = gms }
local pvObj = { getID = function() return 1 end, getPosition = function() return { x = 0, y = 0, z = 0 } end }
local sent = {}
local cars = { { id = 1, x = 0 }, { id = 2, x = 30 }, { id = 3, x = 500 } }
local function mkCar(c)
  return { getID = function() return c.id end, getPosition = function() return { x = c.x, y = 0, z = 0 } end, queueLuaCommand = function(_, cmd) sent[#sent + 1] = c.id .. ':' .. cmd end }
end
local objs = {}
for i, c in ipairs(cars) do objs[i - 1] = mkCar(c) end
be = { getPlayerVehicleID = function() return 1 end, getObjectByID = function(_, id) return objs[id - 1] end, getObjectCount = function() return 3 end,
  getObject = function(_, i) return objs[i] end, setGroundModel = function(_, name, cd) setCalls = setCalls + 1 end, getPlayerVehicle = function() return objs[0] end }
function getAllVehicles() return { objs[0], objs[1], objs[2] } end
function getObjectByID(id) return objs[id - 1] end
function castRayStatic() return 999 end
local files = {}
function jsonReadFile(f) return files[f] end
function jsonWriteFile(f, t) files[f] = t end

local M = dofile('mod/lua/ge/extensions/carSurfaceFx/marks.lua')
M.onExtensionLoaded()
local S = M.settings()
assert(S.takeover == true, 'takeover is on by default')
assert(gms.DIRT.cdata.skidMarks == false and gms.ASPHALT.cdata.skidMarks == false and M.takeoverActive(), 'the game\'s own marks are hidden')
assert(setCalls == 2, 'one ground model call each')

-- marks are stored and drawn in one batch per surface and kind
for i = 1, 3 do M.addSegment(i, 0, 0, i + 0.5, 0, 0, 'dirt', 1, 0.8) end
for i = 1, 4 do M.addSegment(i, 1, 0, i + 0.5, 1, 0, 'sand', 0, 0.5) end
M.addSegment(0, 0, 0, 1, 0, 0, 'lava', 1, 0.5)
assert(M.count('skid') == 3 and M.count('track') == 4, 'unknown surfaces are ignored: ' .. M.count('skid') .. ' ' .. M.count('track'))
M.onPreRender(0.016)
assert(drawn == 7 and batches == 2, 'one batch per surface and kind: ' .. drawn .. ' decals in ' .. batches)

-- the cull distance, measured from the camera
drawn, batches = 0, 0
cam.x = 1000
M.onPreRender(0.016)
assert(drawn == 0, 'far from the camera nothing is drawn')
cam.x = 0

-- the ring buffer: the oldest are recycled
M.configure({ skidCount = 10 })
M.clear()
for i = 1, 25 do M.addSegment(i, 0, 0, i + 0.5, 0, 0, 'mud', 1, 0.5) end
assert(M.count('skid') == 10, 'the ring holds skidCount marks: ' .. M.count('skid'))

-- a zero-length step is not a mark
M.clear()
M.addSegment(1, 1, 1, 1, 1, 1, 'dirt', 1, 0.5)
assert(M.count('skid') == 0, 'no zero-length marks')

-- the cars that mark: the player's and the nearest ones within range (car 3 is 500 m away)
sent = {}
M.onUpdate(2.5)
local on = {}
for _, c in ipairs(sent) do on[#on + 1] = c end
local joined = table.concat(on, '\n')
assert(joined:find('1:[^\n]*setConfig%(0%.1200, true, true%)'), 'the player car marks: ' .. joined)
assert(joined:find('2:[^\n]*, true%)'), 'a near car marks')
assert(joined:find('3:[^\n]*, false%)'), 'a car out of range does not')

-- off: nothing is drawn and the game's own marks come back
M.configure({ enabled = false })
drawn = 0
M.addSegment(0, 0, 0, 1, 0, 0, 'dirt', 1, 0.5)
M.onPreRender(0.016)
assert(drawn == 0, 'off draws nothing')
assert(gms.DIRT.cdata.skidMarks == true and gms.ASPHALT.cdata.skidMarks == true and not M.takeoverActive(), 'the game\'s own marks are back')
M.configure({ enabled = true })
assert(gms.DIRT.cdata.skidMarks == false, 'and away again when switched on')
M.onExtensionUnloaded()
assert(gms.DIRT.cdata.skidMarks == true, 'unloading hands the game its marks back')

-- the old mod's settings file is read once when ours does not exist yet
files['settings/fatkiwi_skidMarkEnhancer.json'] = { skidCount = 1234, mats = { dirt = { skid = { width = 0.5 } } }, takeover = false }
files['settings/carSurfaceFx_marks.json'] = nil
M.load()
assert(M.settings().skidCount == 1234 and M.settings().mats.dirt.skid.width == 0.5 and M.settings().takeover == false, 'values carried over from the old mod')
assert(M.settings().mats.dirt.skid.opacity == 0.8, 'the rest is the default')
M.save()
files['settings/fatkiwi_skidMarkEnhancer.json'] = nil
M.load()
assert(M.settings().skidCount == 1234, 'our own file is read next time')
-- get and set by path (what the Mods menu uses)
M.load()
assert(M.get('mats.dirt.skid.width') ~= nil and M.get('mats.lava.skid.width') == nil, 'get by path, unknown paths answer nil')
assert(M.set('mats.dirt.skid.width', 0.4) and M.get('mats.dirt.skid.width') == 0.4, 'set by path')
assert(M.set('mats.dirt.skid.width', 'wide') == false and M.set('nothing.here', 1) == false, 'a wrong type or path is refused')
assert(M.set('mats.dirt.skid.color', { 1, 0, 0 }) and M.get('mats.dirt.skid.color')[1] == 1, 'colours are set as lists')
-- a throwing hook switches the module off, logs once and is not called again
local logs, calls = {}, 0
function log(level, tag, msg) logs[#logs + 1] = level .. ' ' .. tag .. ' ' .. msg end
M.configure({ enabled = true })
M.clear()
M.addSegment(0, 0, 0, 1, 0, 0, 'dirt', 1, 0.5)
Engine.Render.DynamicDecalMgr.addDecals = function() calls = calls + 1 error('boom') end
M.onPreRender(0.016) M.onPreRender(0.016) M.onPreRender(0.016)
assert(calls == 1 and #logs == 1 and logs[1]:find('boom'), 'one error: off, one log line, no second call (' .. calls .. ' calls, ' .. #logs .. ' lines)')
assert(M.failure() and M.resume() == 'resumed' and not M.failure(), 'resume() tries again')
print('carSurfaceFx marks: ok')
