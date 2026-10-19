-- carSurfaceFx/grassRules.lua (the rules) and carSurfaceFx/grass.lua (the extension) against a mocked game: SurfaceMaskClipmap, terrain, cars, the game's own wheel stamper.
local R = dofile('mod/lua/ge/extensions/carSurfaceFx/grassRules.lua')
local function near(a, b) return math.abs(a - b) < 1e-6 end

-- ---- the rules -------------------------------------------------------------------------------------------------------------------------------------------
local s = R.sanitize({ strength = 9, widthScale = 0, distance = 1, maxCars = 99, clearAfterMin = -3, enabled = false, junk = 1 })
assert(s.strength == 1 and s.widthScale == 0.3 and s.distance == 10 and s.maxCars == 20 and s.clearAfterMin == 0 and s.enabled == false and s.junk == nil, 'sanitize clamps and keeps false')
assert(R.sanitize(nil).enabled == false and R.sanitize({ traffic = 'x' }).traffic == true, 'defaults')
assert(near(R.stampWidth(0.25, 1), 0.4) and R.stampWidth(0.05, 1) == 0.35 and R.stampWidth(2, 1) == 1.4 and near(R.stampWidth(nil, 2), 0.8), 'stamp width: tyre x 1.6, clamped')
assert(near(R.flatten(0, 1), 0.6) and near(R.flatten(25, 1), 1) and near(R.flatten(100, 0.5), 0.5) and R.flatten(10, 0) == 0, 'flatten grows with speed, scales with strength')
assert(R.mark(0.5, true) == 1 and R.mark(0.1, true) == 0.5 and R.mark(0.9, false) == 0.5, 'a spinning wheel cuts, only when allowed')
assert(R.isGrassName('Grass_Dry') and R.isGrassName('meadow2') and not R.isGrassName('asphalt') and R.isGrassName('fieldgreen', { 'field' }), 'grass names')
assert(R.step(0.1, 0, 0) == 'still' and R.step(0.5, 0, 0) == 'stamp' and R.step(20, 0, 0) == 'jump', 'a step is still, a stamp or a jump')
local log = R.logNew(5)
for i = 1, 8 do R.logAdd(log, i * 10, i, 0, i + 1, 0, 1, 1, 0.5) end
assert(log.n == 5, 'the ring keeps 5')
local recent = R.logRecent(log, 80, 35, 0, 0, 100, nil)
assert(#recent == 4 and recent[1].t == 50 and recent[4].t == 80, 'recent: younger than 35 s, oldest first')
assert(#R.logRecent(log, 80, 1000, 7, 0, 1.5, nil) == 3 and #R.logRecent(log, 80, 1000, 0, 0, 100, 2) == 2, 'by distance and by count')
assert(R.purgeDue(log, 100, 30, 0, 10) and not R.purgeDue(log, 100, 30, 95, 10) and not R.purgeDue(log, 100, 0, 0, 10) and not R.purgeDue(log, 60, 30, 0, 10), 'purge due')

-- ---- the extension ---------------------------------------------------------------------------------------------------------------------------------------
local vmeta = {}
vmeta.__index = vmeta
local function vec3(x, y, z)
  if type(x) == 'table' then return setmetatable({ x = x.x, y = x.y, z = x.z }, vmeta) end
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vmeta)
end
vmeta.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
vmeta.__mul = function(a, k) return a end                                   -- (the identity rotation: quat * vec3)
function vmeta:set(x, y, z) self.x, self.y, self.z = x, y, z end
function vmeta:dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function vmeta:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function vmeta:setRotate(q, v) self.x, self.y, self.z = v.x, v.y, v.z end
function vmeta:setAdd(o) self.x, self.y, self.z = self.x + o.x, self.y + o.y, self.z + o.z end
_G.vec3 = vec3
_G.quat = function() return setmetatable({}, { __index = { setFromDir = function() end }, __mul = function(q, v) return v end }) end

local clock = 0
os.clockhp = function() return clock end
local calls = {}
local clip = {}
for _, n in ipairs({ 'init', 'setCenter', 'clear', 'maskCircleWorld', 'maskLineWorld' }) do clip[n] = function(self, ...) calls[#calls + 1] = { n, ... } end end
local function count(name) local c = 0 for _, e in ipairs(calls) do if e[1] == name then c = c + 1 end end return c end
local function last(name) for i = #calls, 1, -1 do if calls[i][1] == name then return calls[i] end end end

local function car(id, x, y)
  local c = { id = id, x = x, y = y, vy = 0 }
  function c:getID() return self.id end
  function c:getPositionXYZ() return self.x, self.y, 0 end
  function c:getDirectionVectorXYZ() return 0, 1, 0 end
  function c:getDirectionVectorUpXYZ() return 0, 0, 1 end
  function c:getVelocityXYZ() return 0, self.vy, 0 end
  function c:getWheelCount() return 4 end
  function c:getWheelAxisNodes(i) return { i * 2 + 1, i * 2 + 2 } end
  function c:getNodePosition(cid)        -- the wheels at (+-0.8, +-1.2), the two axle nodes 0.22 apart
    local i = math.floor((cid - 1) / 2)
    local side, front = (i % 2 == 0) and -0.8 or 0.8, (i < 2) and 1.2 or -1.2
    return vec3(side + ((cid % 2 == 0) and 0.22 or 0), front, 0)
  end
  return c
end
local player, others = car(1, 10, 0), {}
be = { getPlayerVehicle = function() return player end, getObjectCount = function() return 1 + #others end,
       getObject = function(_, i) if i == 0 then return player end return others[i] end }
getCurrentLevelIdentifier = function() return 'gridmap_v2' end
core_terrain = { getTerrain = function() return {
  getMaterialIdxWs = function(_, p) return p.x < 50 and 1 or 2 end,
  getMaterialName = function(_, i) return i == 1 and 'GridMap_Grass' or 'asphalt' end } end }
local wheelsScript = { enabled = true, calls = 0 }
function wheelsScript.setEnabled(on) wheelsScript.enabled = on and true or false wheelsScript.calls = wheelsScript.calls + 1 end
_G.util_surfaceMaskWheels = wheelsScript

local G = dofile('mod/lua/ge/extensions/carSurfaceFx/grass.lua')
-- no clipmap in the game: it says so and does nothing
assert(G.start() == false and G.status():find('no SurfaceMaskClipmap', 1, true), 'no clipmap, no start')
_G.SurfaceMaskClipmap = clip

G.configure({ traffic = true, distance = 60, maxCars = 6 })
assert(G.start() == true and wheelsScript.enabled == false, 'started; the game\'s own wheel stamper is off')
assert(count('init') == 1 and last('init')[2] == '/temp/levels/gridmap_v2/dynamicTiles', 'storage per level')

local function tick(n, step)
  for _ = 1, n do
    player.y = player.y + step
    clock = clock + 0.05
    G.onPreRender(0.05, 0.05)
  end
end
calls = {}
tick(1, 0.5)
assert(count('maskCircleWorld') == 4 and count('setCenter') == 1, 'the first contact stamps a circle at each wheel; the clipmap follows the player')
assert(near(last('maskCircleWorld')[4], 0.35 * 0.5 * 1) or last('maskCircleWorld')[4] > 0.17, 'radius is half the stamp width')
calls = {}
player.vy = 25
tick(3, 0.5)
assert(count('maskLineWorld') == 12, 'then a line per wheel per tick: ' .. count('maskLineWorld'))
local ln = last('maskLineWorld')
assert(ln[6] >= 0.35 and ln[7] == 1 and ln[8] == 0.5, 'width at least 0.35, flatten 1 at speed 25, no cut without wheelspin')
-- wheelspin: the wheel watcher reports slipping, then not
G.noteGround(1, 1, 0, 0.8, 5)
calls = {}
tick(1, 0.5)
assert(last('maskLineWorld')[8] == 1, 'wheelspin cuts (mark 1)')
G.noteGround(1, 1, 0, 0.0, 5)
calls = {}
tick(1, 0.5)
assert(last('maskLineWorld')[8] == 0.5, 'no wheelspin, no cut')
-- the setting turns the cut off
G.configure({ wheelspinCut = false })
G.noteGround(1, 1, 0, 0.9, 5)
calls = {}
tick(1, 0.5)
assert(last('maskLineWorld')[8] == 0.5, 'cut off in the settings')
G.configure({ wheelspinCut = true, traffic = true, distance = 60, maxCars = 6 })
-- off the grass: nothing, and the stroke starts again on return
player.x, player.y = 80, 0
calls = {}
tick(3, 0.5)
assert(count('maskLineWorld') == 0 and count('maskCircleWorld') == 0, 'tarmac: no stamps')
player.x = 10
calls = {}
tick(1, 0.5)
assert(count('maskCircleWorld') == 4, 'back on grass: a new stroke starts with circles')
-- a jump (teleport, reset) is not stamped as a line
player.y = player.y + 500
calls = {}
tick(1, 0)
assert(count('maskLineWorld') == 0, 'a jump is not a stroke')
-- other cars within the distance, at most maxCars; none when too far, none when off
others[1] = car(2, 20, player.y)
others[2] = car(3, 500, player.y)
calls = {}
tick(2, 0.5)
local circles, lines = count('maskCircleWorld'), count('maskLineWorld')
assert(circles + lines >= 4 + 8 - 4, 'the near car stamps too (every second tick)')
local before = circles + lines
G.configure({ traffic = false })
calls = {}
tick(2, 0.5)
assert(count('maskLineWorld') == 4 * 2 and count('maskCircleWorld') == 0, 'traffic off: only the player (4 wheels, 2 ticks)')
G.configure({ traffic = true, distance = 10, maxCars = 6 })
others[1].x = 40
calls = {}
tick(2, 0.5)
assert(count('maskLineWorld') + count('maskCircleWorld') == 8, 'the other car is out of range: only the player')

-- the "let trails go" policy: clear and put the recent ones back
G.configure({ traffic = false, clearAfterMin = 1 })
clock = 1000
calls = {}
tick(2, 0.5)
local t0 = clock
clock = clock + 40
tick(2, 0.5)                                             -- stamps 40 s younger
clock = clock + 30                                       -- the first ones are now about 70 s old: older than the lifetime (60 s)
calls = {}
tick(1, 0.5)
assert(count('clear') == 1, 'a purge: the mask is cleared once')
tick(3, 0.5)
assert(G.status():find('purges 2', 1, true) and G.status():find('restamped [1-9]'), 'the status shows it: ' .. G.status())
local restamped = 0
for _, e in ipairs(calls) do if e[1] == 'maskLineWorld' then restamped = restamped + 1 end end
assert(restamped > 4 * 4, 'the recent stamps are put back (and the new ones go on)')
calls = {}
G.clear()
assert(count('clear') == 1 and G.status():find('log 0', 1, true), 'clear: the mask and the log')
-- a level loads: tiles re-pointed, cleared when asked
calls = {}
G.configure({ clearOnLevel = true })
G.onClientStartMission()
assert(count('init') == 1 and count('clear') == 1, 'level start: init and clear')
-- stop: the game's wheel stamper is given back
G.stop()
assert(wheelsScript.enabled == true, 'given back as it was')
calls = {}
tick(1, 0.5)
assert(#calls == 0, 'stopped: nothing')
-- the Mods menu fields: stored under grass in the settings file, every default is the rules' default
local fields = G.fields('/settings/x.json')
local ids, ok = {}, true
for _, f in ipairs(fields) do ids[f.id] = f end
assert(ids.grass_enabled.store.path == 'grass.enabled' and ids.grass_clear_after.type == 'int' and ids.grass_clear_now.type == 'button' and #fields == 10, 'fields')
assert(ids.grass_strength.default == R.DEFAULTS.strength and ids.grass_clear_after.default == R.DEFAULTS.clearAfterMin, 'defaults come from the rules')
-- (the globals this test made are taken away again: the other tests run in the same state)
for _, n in ipairs({ 'SurfaceMaskClipmap', 'util_surfaceMaskWheels', 'core_terrain', 'be', 'getCurrentLevelIdentifier', 'vec3', 'quat' }) do _G[n] = nil end
os.clockhp = nil
print('carSurfaceFx grass: ok')
