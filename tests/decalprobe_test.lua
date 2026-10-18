-- carSurfaceFx/decalProbe.lua against a mocked game: the strips are made, drawn each frame by the decal manager, and cleared again.
local vmeta = {}
vmeta.__index = vmeta
vmeta.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vmeta) end
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmeta) end
vmeta.__mul = function(a, k) return setmetatable({ x = a.x * k, y = a.y * k, z = a.z * k }, vmeta) end
function vmeta:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function vmeta:normalized() local l = self:length() return setmetatable({ x = self.x / l, y = self.y / l, z = self.z / l }, vmeta) end
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vmeta) end
function ColorF(r, g, b, a) return { r = r, g = g, b = b, a = a } end
local car = { getPosition = function() return vec3(100, 50, 3) end, getDirectionVector = function() return vec3(0, 1, 0) end }
function getPlayerVehicle() return car end
local objs, nextId, added = {}, 1, nil
function createObject(class)
  local o = { class = class, fields = {}, nodes = {}, id = nextId }
  nextId = nextId + 1
  function o:setField(k, i, v) self.fields[k] = v end
  function o:registerObject() objs[self.id] = self end
  function o:insertNode(pos, width, idx) self.nodes[#self.nodes + 1] = { pos, width } end
  function o:getID() return self.id end
  function o:deleteObject() objs[self.id] = nil end
  return o
end
scenetree = { MissionGroup = { add = function() end }, findObjectById = function(id) return objs[id] end,
              findObject = function(n) return n == 'm_dirt_tiretracks' and { getField = function(_, k) return 'f:' .. k end } or nil end }
Engine = { Render = { DynamicDecalMgr = { addDecals = function(pool, n) added = { pool = pool, n = n } end } } }
local P = dofile('mod/lua/ge/extensions/carSurfaceFx/decalProbe.lua')
assert(P.run():find('4 decal manager strips', 1, true), 'both rows made')
local roads = 0
for _, o in pairs(objs) do if o.class == 'DecalRoad' then roads = roads + 1 assert(o.fields.material == 'BlankWhite' and #o.nodes == 2) end end
assert(roads == 4, 'four decal roads')
P.onPreRender()
assert(added and added.n == 4 and added.pool[1].texture:find('probe_white', 1, true), 'the decal manager is given the strips every frame')
assert(added.pool[1].position.x < 100 and objs[1].nodes[1][1].x > 100, 'decal manager strips on the left, roads on the right')
assert(P.road('nope'):find('not loaded', 1, true) and P.road('m_dirt_tiretracks'):find('14 m', 1, true))
assert(P.info('m_dirt_tiretracks'):find('normalMap=f:normalMap', 1, true))
P.clear()
assert(next(objs) == nil, 'everything removed')
added = nil
P.onPreRender()
assert(added == nil, 'nothing drawn after clear')
print('carSurfaceFx decal probe: ok')
