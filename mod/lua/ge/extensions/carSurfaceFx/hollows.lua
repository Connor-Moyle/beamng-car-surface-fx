-- Car Surface FX: visual terrain hollows. A wheel pressing soft ground lowers the terrain's drawn height a little (to the ground's own sink depth, 15 cm at most), so the tyre looks bedded
-- in and the track a shallow trough. VISUAL ONLY: the heights are written to the TerrainBlock's render copy and the physics copy is never rebuilt (probe by connor-80: the hollow is drawn,
-- castRayStatic and getSurfaceHeightBelow still give the original height, a car rolls over it). Never called here: be:reloadCollision(), TerrainBlock:save(), setTerrainDirty().
-- The engine call updateGrid costs about 3.7 ms whatever the size, so the dirty vertices are written at most once every flushInterval seconds. Every original height is kept and put
-- back by restore() (level end, the module unloading, the editor opening, the switch off). Rules: hollowrules.lua (tested).
local M = {}

local rules = require('carSurfaceFx/hollowrules')

local TAG = 'carSurfaceFx_hollows'
local st = rules.newState()
local orig = {}                       -- key -> the vertex's own height (local to the block), kept the first time it is touched
local tb, px, py, sq                  -- the terrain block, its position and the metres between vertices
local timer = 0
local failed                          -- why hollows are off (no terrain block, an engine call failed), nil while they work
local stats = { flushes = 0, writes = 0, ms = 0, restored = 0 }
M.stats = stats

local function block()
  if tb then return tb end
  local ok, b = pcall(function() return core_terrain and core_terrain.getTerrain and core_terrain.getTerrain() end)
  if not (ok and b) then return nil end
  local okp, p = pcall(function() return b:getPosition() end)
  local oks, s = pcall(function() return b:getSquareSize() end)
  if not (okp and p and oks and type(s) == 'number' and s > 0) then return nil end
  tb, px, py, sq = b, p.x, p.y, s
  return tb
end

-- Street Legal's gate (sl/core/gpugate), when that mod is there: the GPU was lost when terrain edits and its rain material reloads came close together, so they take turns
local gate
local function sharedGate()
  if gate == nil then
    local ok, g = pcall(require, 'sl/core/gpugate')
    gate = ok and type(g) == 'table' and g.terrainEditOk and g or false
  end
  return gate
end

local function fail(why)
  failed = tostring(why)
  log('W', TAG, 'terrain hollows off: ' .. failed)
end

-- a wheel at world (x, y) pressing `kind` with `press` (rutrules.depth)
function M.stamp(cfg, x, y, kind, press)
  if failed or not cfg.enabled or not block() then return end
  local fp = rules.footprint(x, y, px, py, sq)
  rules.stamp(st, fp, kind, press, cfg)
end

local function apply(list, box)
  local t0 = os.clock()
  for _, v in ipairs(list) do
    local k = rules.key(v[1], v[2])
    if orig[k] == nil then orig[k] = tb:getHeightGrid(v[1], v[2]) end
    tb:setHeightGrid(v[1], v[2], rules.height(orig[k], st.depth[k] or 0))
  end
  tb:updateGrid(vec3(box[1], box[2], 0), vec3(box[3], box[4], 0))
  stats.flushes, stats.writes, stats.ms = stats.flushes + 1, stats.writes + #list, (os.clock() - t0) * 1000
end

-- every frame (cheap): at the flush interval write what changed
function M.update(cfg, dt)
  if failed or not tb or st.dirtyN == 0 then return end
  timer = timer + dt
  if timer < cfg.flushInterval then return end
  local g, now = sharedGate(), os.clock()
  if g and not g.terrainEditOk(now) then return end                -- (the edits stay dirty and go out at the next free flush)
  timer = 0
  local list, box = rules.takeDirty(st)
  if not list then return end
  local ok, err = pcall(apply, list, box)
  if not ok then fail(err) end
  if g and g.terrainEdited then g.terrainEdited(now) end                                -- (the wet world leaves the GPU alone for a moment after our edit)
end

-- put every height back (the original of each touched vertex) and tell the engine, then forget it all
function M.restore()
  if tb and next(orig) then
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    local ok = pcall(function()
      for k, h in pairs(orig) do
        local gx, gy = math.floor(k / 65536), k % 65536
        tb:setHeightGrid(gx, gy, h)
        if gx < x0 then x0 = gx end
        if gx > x1 then x1 = gx end
        if gy < y0 then y0 = gy end
        if gy > y1 then y1 = gy end
        stats.restored = stats.restored + 1
      end
      tb:updateGrid(vec3(x0, y0, 0), vec3(x1, y1, 0))
    end)
    if not ok then log('W', TAG, 'terrain hollows: the heights could not be put back') end
  end
  st, orig, timer, tb = rules.newState(), {}, 0, nil
end

-- the level is ending or new: its terrain block is being destroyed or is another one, so write nothing; forget the heights (the level unload discards the render copy)
function M.forget() st, orig, timer, tb = rules.newState(), {}, 0, nil end

-- the drawn ground height at a point, for the marks that must sit on the visible surface (berms, puddles); nil while no hollow is there or hollows are off
function M.groundZ(x, y)
  if not tb or failed or st.n == 0 then return nil end
  local ok, z = pcall(function() return tb:getHeight(vec3(x, y, 0)) end)
  if ok and type(z) == 'number' then return z end
end

function M.available() return failed == nil end
function M.why() return failed end
function M.retry() failed = nil end
function M.count() return st.n end
function M.status()
  return string.format('hollows %d vertices, %d flushes (%d writes, last %.1f ms), restored %d%s', st.n, stats.flushes, stats.writes, stats.ms, stats.restored, failed and (', OFF: ' .. failed) or '')
end

return M
