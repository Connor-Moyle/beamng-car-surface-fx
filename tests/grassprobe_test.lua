-- carSurfaceFx/grassProbe.lua against a mocked SurfaceMaskClipmap: the calls and their arguments.
local vmeta = {}
vmeta.__index = vmeta
vmeta.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vmeta) end
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmeta) end
vmeta.__mul = function(a, k) return setmetatable({ x = a.x * k, y = a.y * k, z = a.z * k }, vmeta) end
function vmeta:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function vmeta:normalized() local l = self:length() return setmetatable({ x = self.x / l, y = self.y / l, z = self.z / l }, vmeta) end
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vmeta) end
local car = { getPosition = function() return vec3(100, 50, 3) end, getDirectionVector = function() return vec3(0, 1, 0) end }
function getPlayerVehicle() return car end
function getCurrentLevelIdentifier() return 'gridmap_v2' end
local calls = {}
local function rec(name) return function(self, ...) calls[#calls + 1] = { name, ... } end end
local P = dofile('mod/lua/ge/extensions/carSurfaceFx/grassProbe.lua')
assert(P.flatten():find('no SurfaceMaskClipmap', 1, true) or P.flatten():find('there is no', 1, true), 'a game without the mask says so')
SurfaceMaskClipmap = { init = rec('init'), setCenter = rec('setCenter'), maskCircleWorld = rec('circle'), maskLineWorld = rec('line'), clear = rec('clear'),
  setDebugEnabled = rec('debug'), getDebugState = function() return { residentPages = 7, dispatchSubmitMs = 0.1 } end }
assert(P.flatten():find('flattened', 1, true))
assert(calls[1][1] == 'init' and calls[1][2] == '/temp/levels/gridmap_v2/dynamicTiles' and calls[2][1] == 'setCenter' and calls[2][2] == 100)
local circle, line
for _, c in ipairs(calls) do if c[1] == 'circle' then circle = c elseif c[1] == 'line' then line = c end end
assert(circle[2] == 100 and circle[3] == 58 and circle[4] == 2.5 and circle[5] == 1 and circle[6] == 0, 'a circle 8 m ahead, flatten 1, no cut')
assert(line[6] == 1.6 and line[7] == 1 and line[8] == 0 and line[2] > 100, 'a line to the right')
calls = {}
P.cut()
for _, c in ipairs(calls) do if c[1] == 'circle' then circle = c end end
assert(circle[6] == 1, 'cut: mark 1')
calls = {}
assert(P.fan():find('five circles', 1, true))
local n = 0
for _, c in ipairs(calls) do if c[1] == 'circle' then n = n + 1 end end
assert(n == 5, 'five circles')
assert(P.status():find('residentPages=7', 1, true))
assert(P.clear():find('cleared', 1, true))
print('carSurfaceFx grass probe: ok')
