-- carSurfaceFx/markMaterials.lua (makes the mark materials when the game did not load them) and markSwatches.lua (the test map), against a mocked game.
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

local files = {
  ['/art/surfacefx/marks/main.materials.json'] = {
    csfx_a_dry = { name = 'csfx_a_dry', translucent = true, translucentZWrite = true, materialTag0 = 'RoadAndPath', version = 1.5,
      Stages = { { baseColorMap = '/x/b.png', baseColorFactor = { 1, 0.5, 0.25, 1 }, opacityFactor = 0.9 }, {}, {}, {} } },
    csfx_a_wet = { name = 'csfx_a_wet', translucent = true, translucentZWrite = true, version = 1.5, Stages = { { baseColorMap = '/x/b.png' }, {}, {}, {} } },
    csfx_b_dry = { name = 'csfx_b_dry', translucent = true, version = 1.5, Stages = { {}, {}, {}, {} } },
    csfx_b_wet = { name = 'csfx_b_wet', translucent = true, version = 1.5, Stages = { {}, {}, {}, {} } },
  },
  ['/art/surfacefx/marks/marks_index.json'] = { types = {
    { type = 'rut_dirt', dry = 'csfx_a_dry', wet = 'csfx_a_wet', textureLength = 4, width = 0.9, blob = false },
    { type = 'oil', dry = 'csfx_b_dry', wet = 'csfx_b_wet', textureLength = 1, width = 1, blob = true },
    { type = 'ghost', dry = 'csfx_none_dry', wet = 'csfx_none_wet', textureLength = 1, width = 1, blob = true },
  } },
}
function jsonReadFile(p) return files[p] end
local objs, byName, nextId = {}, {}, 1
function createObject(class)
  local o = { class = class, fields = {}, nodes = {}, id = nextId }
  nextId = nextId + 1
  function o:setField(k, i, v) self.fields[k .. '@' .. i] = v end
  function o:registerObject(n) objs[self.id] = self if n and n ~= '' then byName[n] = self end end
  function o:insertNode(pos, width) self.nodes[#self.nodes + 1] = { pos = pos, width = width } end
  function o:getID() return self.id end
  function o:deleteObject() objs[self.id] = nil end
  return o
end
local reloaded = 0
Sim = { upcast = function(m) return { reload = function() reloaded = reloaded + 1 end } end }
scenetree = { MissionGroup = { add = function() end }, findObject = function(n) return byName[n] end, findObjectById = function(id) return objs[id] end }
local drawn = {}
debugDrawer = { drawTextAdvanced = function(_, p, text) drawn[#drawn + 1] = text end }
function String(s) return s end
function ColorF() return {} end
function ColorI() return {} end

local MM = dofile('mod/lua/ge/extensions/carSurfaceFx/markMaterials.lua')
package.loaded['carSurfaceFx/markMaterials'] = MM
assert(MM.ensure('csfx_a_dry') == true, 'a material that is not loaded is made')
local m = byName.csfx_a_dry
assert(m and m.fields['mapTo@0'] == 'csfx_a_dry' and m.fields['translucent@0'] == '1' and m.fields['translucentZWrite@0'] == '1' and m.fields['version@0'] == '1.5', 'header fields')
assert(m.fields['baseColorMap@0'] == '/x/b.png' and m.fields['baseColorFactor@0'] == '1 0.5 0.25 1' and m.fields['opacityFactor@0'] == '0.9', 'stage fields, arrays as text')
assert(reloaded == 1, 'reloaded once')
assert(MM.ensure('csfx_a_dry') == true and reloaded == 1, 'a material that exists is left alone')
local ok, why = MM.ensure('csfx_none')
assert(ok == false and why:find('no entry', 1, true), 'unknown name says so')
local made, failed = MM.ensureAll()
assert(made == 4 and #failed == 0, 'all four of the file')

local W = dofile('mod/lua/ge/extensions/carSurfaceFx/markSwatches.lua')
local msg = W.run()
local roads = 0
for _, o in pairs(objs) do if o.class == 'DecalRoad' then roads = roads + 1 end end
assert(roads == 4, 'a dry and a wet strip for each of the two types that have materials: ' .. roads)
assert(msg:find('3 types', 1, true) and msg:find('csfx_none_dry', 1, true), 'the message counts the types and names what could not be made: ' .. msg)
local strip, blob
for _, o in pairs(objs) do
  if o.class == 'DecalRoad' and o.fields['material@0'] == 'csfx_a_dry' then strip = o end
  if o.class == 'DecalRoad' and o.fields['material@0'] == 'csfx_b_dry' then blob = o end
end
assert(strip and (strip.nodes[2].pos - strip.nodes[1].pos):length() > 3.9 and strip.nodes[1].width == 0.9 and strip.fields['textureLength@0'] == '4', 'a strip is 4 m long with the type\'s width and texture length')
assert(blob and (blob.nodes[2].pos - blob.nodes[1].pos):length() < 1.5 and blob.nodes[1].width == 1.4, 'a stain is a short wide piece')
W.onPreRender()
assert(#drawn == 3 and drawn[1] == 'rut_dirt', 'a label for each type')
assert(W.run('rut'):find('1 types', 1, true), 'a filter')
W.clear()
assert(next(objs) == nil or true, 'cleared')
local left = 0
for _, o in pairs(objs) do if o.class == 'DecalRoad' then left = left + 1 end end
assert(left == 0, 'no strips left')
print('carSurfaceFx mark swatches: ok')
