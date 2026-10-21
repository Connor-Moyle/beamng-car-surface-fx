-- Rubber marbles on the road, game side (carSurfaceFx/marbles.lua with the tyres.lua wiring): patches from debris events, scuffing, cap, drawing in one call per texture, packing for the car.
log = function() end
local drawn = {}
local vec = function(x, y, z) local v = { x = x, y = y, z = z } function v.set(s, a, b, c) s.x, s.y, s.z = a, b, c end return v end
vec3 = vec
ColorF = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
local sent = {}
local veh = { queueLuaCommand = function(_, c) sent[#sent + 1] = c end }
be = { getObjectByID = function(_, id) return id == 7 and veh or nil end, getPlayerVehicleID = function() return 7 end }
extensions = { hook = function() end }
function jsonEncode(t) return 'J' end
function jsonDecode(s) return {} end
core_environment = { groundModels = {} }
Engine = { Render = { DynamicDecalMgr = { addDecals = function(pool, n) drawn[#drawn + 1] = { tex = pool[1].texture, n = n } end } } }
core_camera = { getPosition = function() return { x = 0, y = 0, z = 0 } end }
local T = dofile('mod/lua/ge/extensions/carSurfaceFx/tyres.lua')
local M = require('carSurfaceFx/marbles')

T.configure({ enabled = true })
T.update(0.1, 0)
assert(T.getConfig().marbles.enabled == false, 'marbles ship off')
T.state(7, {}, { { 0, 'debris', 20, 300, 5, 6, 0.5 } })
assert(M.count() == 0, 'off: a debris event leaves nothing on the road')
T.onPreRender(0.016) assert(#drawn == 0, 'off: nothing drawn')

T.configure({ marbles = { enabled = true, burn = true } })
T.state(7, {}, { { 0, 'debris', 20, 300, 5, 6, 0.5 }, { 1, 'debris', 30, 320, 5.5, 6.2, 0.5 }, { 2, 'debris', 10, 100 } })
assert(M.count() == 1 and M.list()[1].g == 50 and M.list()[1].id == 1, 'two bits near each other are one patch; an event without a position is not a patch')
sent = {}
T.update(0.1, 0)
assert(#sent >= 1 and sent[#sent]:find('setMarbles({{5.', 1, true), 'the patch is pushed to the car: ' .. tostring(sent[#sent]))
local before = #sent
T.update(0.1, 0)
assert(#sent == before, 'nothing changed: nothing sent')
T.onPreRender(0.016)
assert(#drawn >= 1 and drawn[1].n >= 3, 'the bits are drawn')
local tot = 0 for _, d in ipairs(drawn) do tot = tot + d.n end
assert(tot <= 160, 'draw cap')
-- one engine call per texture
local seen = {}
for _, d in ipairs(drawn) do assert(not seen[d.tex], 'one call per texture') seen[d.tex] = true end

-- scuff: the car reports a share and the patch shrinks; an unknown id is ignored
T.state(7, {}, { { 0, 'scuff', 1, 50 } })
assert(math.abs(M.list()[1].g - 25) < 0.1, 'a 50 % scuff halves the patch: ' .. M.list()[1].g)
T.state(7, {}, { { 0, 'scuff', 99, 50 } })
assert(math.abs(M.list()[1].g - 25) < 0.1)

-- a hot patch burns (glow drawn), then it is used up; a long time clears everything
M.add(T.getConfig(), 100, 450, 20, 20, 0)
local burning = M.step(T.getConfig(), 0.1, 20, 0)
assert(burning >= 1, 'a hot patch burns')
drawn = {}
T.onPreRender(0.016)
local glow = false for _, d in ipairs(drawn) do if d.tex:find('puddle_1', 1, true) then glow = true end end
assert(glow, 'a burning patch glows')
for _ = 1, 7000 do M.step(T.getConfig(), 0.1, 20, 0) end
assert(M.count() == 0, 'cleared over time')

-- the cap
for i = 1, 40 do M.add(T.getConfig(), 10, 20, 100 * i, 0, 0) end
assert(M.count() == 24, 'at most 24 patches')
-- switching it off clears the road
T.configure({ marbles = { enabled = false } })
T.update(0.1, 0)
assert(M.count() == 0, 'switched off: the road is clean')
T.clearMarbles()
print('carSurfaceFx marbles (game side): ok')
