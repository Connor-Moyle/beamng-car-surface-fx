-- terrain hollows: the rules (hollowrules.lua) and the engine side (hollows.lua) against a mocked TerrainBlock
local R = require('carSurfaceFx/hollowrules')
local cfg = R.defaults()
assert(cfg.enabled == false and cfg.flushInterval >= 1, 'off by default, flushed no more often than once a second')

-- the cap: the ground's own sink depth, never more than maxDepth
assert(R.cap('mud', cfg) == 0.15 and R.cap('snow', cfg) == 0.15 and R.cap('gravel', cfg) == 0.03 and R.cap('tarmac', cfg) == 0, 'cap by ground and maxDepth')

-- grid and footprint: a 1 m grid whose block starts at (-1023.5, -1023.5)
local gx, gy = R.gridOf(10.2, 20.7, -1023.5, -1023.5, 1)
assert(gx == 1034 and gy == 1044, 'grid point: ' .. gx .. ' ' .. gy)
local fp = R.footprint(-1023.5 + 5.0, -1023.5 + 7.0, -1023.5, -1023.5, 1)
local wsum, center = 0, 0
for _, f in ipairs(fp) do wsum = wsum + f[3] if f[1] == 5 and f[2] == 7 then center = f[3] end end
assert(#fp >= 5 and #fp <= 9 and math.abs(center - 1) < 1e-9 and wsum > 1, 'a wheel on a vertex: that vertex weighs 1 and its neighbours less')

-- stamping: deepens by passes, never past the cap; a hard ground and a light wheel do little
local st = R.newState()
assert(R.stamp(st, fp, 'tarmac', 1, cfg) == 0 and st.n == 0, 'hard ground takes nothing')
assert(R.stamp(st, fp, 'mud', 0.001, cfg) == 0, 'a feather takes nothing')
local n1 = R.stamp(st, fp, 'mud', 1, cfg)
local k = R.key(5, 7)
assert(n1 == st.n and n1 >= 5 and st.depth[k] > 0.04 and st.depth[k] < 0.06, 'first pass: ' .. tostring(st.depth[k]))
for _ = 1, 12 do R.stamp(st, fp, 'mud', 1, cfg) end
assert(st.depth[k] <= 0.15 + 1e-9 and st.depth[k] > 0.14, 'deepens to the cap and no further: ' .. st.depth[k])
for _, f in ipairs(fp) do assert(st.depth[R.key(f[1], f[2])] <= 0.15 * f[3] + 1e-9, 'a neighbour is shallower, by its weight') end
local before = st.depth[k]
assert(R.stamp(st, fp, 'mud', 1, cfg) == 0 and st.depth[k] == before, 'nothing more to change at the cap')

-- the vertex limit
local small = { enabled = true, flushInterval = 3, maxDepth = 0.15, maxVerts = 4, passes = 0.35 }
local st2 = R.newState()
R.stamp(st2, fp, 'mud', 1, small)
assert(st2.n == 4, 'no more than maxVerts vertices: ' .. st2.n)

-- dirty list and its box
local list, box = R.takeDirty(st)
assert(#list == st.n and box[1] <= 5 and box[3] >= 5 and box[2] <= 7 and box[4] >= 7, 'dirty vertices with their box')
assert(R.takeDirty(st) == nil, 'and they are clean after')
assert(R.height(3.0, 0.1) == 2.9 and R.height(0.05, 0.1) == 0, 'a vertex goes down by its depth, never below the floor')

-- ---- the engine side against a mocked TerrainBlock
local saved = { vec3 = vec3, core_terrain = core_terrain, log = log }
vec3 = function(x, y, z) return { x = x, y = y, z = z } end
local logs = {}
log = function(level, tag, text) logs[#logs + 1] = level .. ' ' .. tostring(text) end
local heights, sets, grids, collisionCalls = {}, 0, {}, 0
local function H(gx, gy) return heights[gx * 65536 + gy] or 100 end
local block = {
  getPosition = function() return { x = -1023.5, y = -1023.5, z = 0 } end, getSquareSize = function() return 1 end,
  getHeightGrid = function(_, gx, gy) return H(gx, gy) end,
  setHeightGrid = function(_, gx, gy, h) heights[gx * 65536 + gy] = h sets = sets + 1 end,
  updateGrid = function(_, a, b) grids[#grids + 1] = { a.x, a.y, b.x, b.y } end,
  getHeight = function(_, p) return H(math.floor(p.x + 1023.5 + 0.5), math.floor(p.y + 1023.5 + 0.5)) end,
  save = function() error('never saved') end,
}
core_terrain = { getTerrain = function() return block end }
local oldBe = be
be = be or {}
local oldReload = be.reloadCollision
be.reloadCollision = function() collisionCalls = collisionCalls + 1 end
package.loaded['carSurfaceFx/hollows'] = nil
local Hl = require('carSurfaceFx/hollows')
local on = R.defaults()
on.enabled, on.flushInterval = true, 3

Hl.stamp({ enabled = false }, 5, 5, 'mud', 1)
assert(Hl.count() == 0, 'off: nothing')
Hl.stamp(on, -1018.5, -1016.5, 'mud', 1)
assert(Hl.count() >= 5, 'a stamp: the vertices are counted')
Hl.update(on, 1) Hl.update(on, 1)
assert(sets == 0 and #grids == 0, 'nothing is written before the flush interval')
Hl.update(on, 1.1)
assert(sets >= 5 and #grids == 1, 'one flush: the dirty vertices and one updateGrid: ' .. sets .. ' ' .. #grids)
local g = grids[1]
assert(g[1] <= 5 and g[3] >= 5 and g[2] <= 7 and g[4] >= 7, 'the dirty box is in grid coordinates')
assert(H(5, 7) < 100 and H(5, 7) > 99.9, 'the height is lowered a few cm: ' .. H(5, 7))
Hl.update(on, 4)
assert(#grids == 1, 'nothing dirty, no second call')
assert(Hl.groundZ(-1018.5, -1016.5) == H(5, 7), 'the drawn ground height is offered to the marks')
for _ = 1, 8 do Hl.stamp(on, -1018.5, -1016.5, 'mud', 1) Hl.update(on, 3.1) end
assert(H(5, 7) >= 100 - 0.15 - 1e-9 and H(5, 7) < 99.86, 'deepest at the cap: ' .. H(5, 7))
Hl.restore()
assert(H(5, 7) == 100 and #grids >= 3 and Hl.count() == 0, 'restore puts the original heights back and tells the engine')
assert(Hl.groundZ(0, 0) == nil, 'and offers nothing')
assert(collisionCalls == 0, 'the physics copy is never rebuilt')
-- a level that ends writes nothing to its terrain: forget() only drops the state
Hl.stamp(on, -1018.5, -1016.5, 'mud', 1)
Hl.update(on, 3.1)
local setsBefore, gridsBefore = sets, #grids
Hl.forget()
assert(sets == setsBefore and #grids == gridsBefore and Hl.count() == 0 and Hl.groundZ(-1018.5, -1016.5) == nil, 'forget: no height writes, no updateGrid, nothing kept')
heights = {}

-- an engine call that fails switches hollows off, with a reason
block.updateGrid = function() error('no updateGrid') end
Hl.stamp(on, -1018.5, -1016.5, 'mud', 1)
Hl.update(on, 4)
assert(not Hl.available() and Hl.why():find('no updateGrid') and logs[#logs]:find('hollows off'), 'a failing call: off, one log line')

-- with Street Legal's gate present: no flush while it says no (the edits stay dirty), a flush when free, and the gate is told
block.updateGrid = function(_, a, b) grids[#grids + 1] = { a.x, a.y, b.x, b.y } end
local open_, told = false, 0
package.loaded['sl/core/gpugate'] = { terrainEditOk = function() return open_ end, terrainEdited = function() told = told + 1 end }
package.loaded['carSurfaceFx/hollows'] = nil
Hl = require('carSurfaceFx/hollows')
Hl.stamp(on, -1018.5, -1016.5, 'mud', 1)
local g0 = #grids
Hl.update(on, 4)
assert(#grids == g0 and told == 0 and Hl.count() > 0, 'the gate says wait: nothing written')
open_ = true
Hl.update(on, 0.1)
assert(#grids == g0 + 1 and told == 1, 'the gate is free: one flush and the gate is told')
package.loaded['sl/core/gpugate'] = nil
vec3, core_terrain, log = saved.vec3, saved.core_terrain, saved.log
be.reloadCollision = oldReload
be = oldBe
package.loaded['carSurfaceFx/hollows'] = nil
print('carSurfaceFx hollows: ok')
