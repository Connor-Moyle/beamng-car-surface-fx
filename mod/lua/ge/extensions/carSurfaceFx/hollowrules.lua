-- Car Surface FX: the rules of terrain hollows (visual only, docs: SLRR BeamNG Graph/docs/TERRAIN_DEFORM_RESEARCH.md): which vertices of the terrain's height grid a wheel lowers, by how
-- much (never more than the ground's own sink depth), and which ones are dirty and need the engine told. Pure (no game calls), tested by tests/hollow_test.lua. hollows.lua does the engine calls.
local M = {}

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
M.clamp = clamp

-- how deep the game's own physics sinks a tyre into each ground, m (groundmodels: MUD 0.15, SAND 0.1, GRASS 0.05, SNOWBANK 0.25, loose dirt 0.02-0.05); the hollow matches it, never more
M.SINK = { mud = 0.15, snow = 0.25, sand = 0.10, dirt = 0.05, gravel = 0.03 }

function M.defaults()
  return { enabled = false, flushInterval = 3, maxDepth = 0.15, maxVerts = 6000, passes = 0.35 }
end

-- the deepest a hollow on this ground gets: the ground's sink depth, capped by the setting (the cap is also what a collision rebuild would turn into a bump)
function M.cap(kind, cfg) return math.min(M.SINK[kind] or 0, cfg.maxDepth) end

-- the grid point nearest a world position (the block at px, py; squareSize metres between vertices)
function M.gridOf(wx, wy, px, py, sq)
  return math.floor((wx - px) / sq + 0.5), math.floor((wy - py) / sq + 0.5)
end

-- the vertices a wheel at (wx, wy) touches and their weights: the 3 x 3 round the nearest vertex, weighted by distance (1 at the vertex, fading to 0 at 1.5 squares)
function M.footprint(wx, wy, px, py, sq)
  local cx, cy = M.gridOf(wx, wy, px, py, sq)
  local out = {}
  for dx = -1, 1 do
    for dy = -1, 1 do
      local gx, gy = cx + dx, cy + dy
      local ex, ey = (px + gx * sq) - wx, (py + gy * sq) - wy
      local w = 1 - math.sqrt(ex * ex + ey * ey) / (1.5 * sq)
      if w > 0.05 then out[#out + 1] = { gx, gy, w } end
    end
  end
  return out
end

local function key(gx, gy) return gx * 65536 + gy end
M.key = key

function M.newState() return { depth = {}, n = 0, dirty = {}, dirtyN = 0 } end

-- a wheel pressing `kind` with `press` (rutrules.depth: 0..2.5) at the footprint fp: each vertex deepens by `passes` of the wanted depth per pass, never past the cap.
-- Returns the number of vertices that changed.
function M.stamp(st, fp, kind, press, cfg)
  local cap = M.cap(kind, cfg)
  if cap <= 0.002 then return 0 end
  local want = cap * clamp(press, 0, 1)
  if want <= 0.002 then return 0 end
  local changed = 0
  for _, f in ipairs(fp) do
    local k = key(f[1], f[2])
    local cur = st.depth[k]
    if not (cur == nil and st.n >= cfg.maxVerts) then
      local target = math.min(cap, want * f[3])
      local new = math.min(target, (cur or 0) + target * (cfg.passes or 0.35))
      if cur == nil or new > cur + 0.002 then
        if cur == nil then st.n = st.n + 1 end
        st.depth[k] = new
        if not st.dirty[k] then st.dirty[k] = { f[1], f[2] } st.dirtyN = st.dirtyN + 1 end
        changed = changed + 1
      end
    end
  end
  return changed
end

-- the dirty vertices { {gx, gy}, ... } and their bounding box {x0, y0, x1, y1} (grid), and forget that they are dirty
function M.takeDirty(st)
  if st.dirtyN == 0 then return nil end
  local list, x0, y0, x1, y1 = {}, math.huge, math.huge, -math.huge, -math.huge
  for _, v in pairs(st.dirty) do
    list[#list + 1] = v
    if v[1] < x0 then x0 = v[1] end
    if v[1] > x1 then x1 = v[1] end
    if v[2] < y0 then y0 = v[2] end
    if v[2] > y1 then y1 = v[2] end
  end
  st.dirty, st.dirtyN = {}, 0
  return list, { x0, y0, x1, y1 }
end

-- the height a vertex is set to: its original, lowered by its depth (never below the block's floor, 0)
function M.height(orig, depth) return math.max(0, orig - depth) end

return M
