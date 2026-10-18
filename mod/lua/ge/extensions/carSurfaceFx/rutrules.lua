-- Car Surface FX: the rules of ruts (port P4, written fresh): which ground takes a rut, how deep a wheel presses it (the ground's softness x the wheel's load, a spinning wheel digs),
-- how repeated passes along the same track deepen it, and how the wheel path is cut into chunks. Pure (no game calls), tested by tests/ruts_test.lua.
local M = {}

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
M.clamp = clamp

M.KINDS = { 'mud', 'snow', 'sand', 'dirt', 'gravel' }                 -- the grounds that take a rut (the mark materials csfx_rut_<kind>_dry / _wet)

function M.defaults()
  return {
    enabled = false,
    routing = 'road',                                                  -- 'road': small DecalRoads with the lit mark materials; 'decal': the decal manager (the fallback)
    maxRoads = 200,                                                    -- chunks kept (a ring: the oldest are removed)
    maxPerSecond = 6,                                                  -- chunks made per second at most (a DecalRoad rebuilds its mesh when made)
    step = 0.6,                                                        -- m between samples of a wheel path
    chunkPoints = 5,                                                   -- samples in a chunk
    minDepth = 0.15,                                                   -- the least pressing that leaves a rut
    maxLayers = 3,                                                     -- how many passes along one track still deepen it
    widthScale = 1.0,
    wetAbove = 0.3, dryBelow = 0.2,                                    -- the wet material from this wetness, the dry one again below the other (a little hysteresis)
    cullRadius = 120,
    others = { enabled = false, maxCars = 3, range = 50 },
    kinds = {
      mud = { enabled = true, soft = 1.00 }, snow = { enabled = true, soft = 0.85 }, sand = { enabled = true, soft = 0.75 },
      dirt = { enabled = true, soft = 0.55 }, gravel = { enabled = true, soft = 0.35 },
    },
  }
end

-- how deeply a wheel presses the ground: softness x load (4000 N on a wheel is a normal car; a truck presses twice) x a spinning wheel digging (slip in m/s). 0 = nothing.
function M.depth(kind, loadN, slip, cfg)
  local k = cfg.kinds[kind]
  if not k or not k.enabled then return 0 end
  local load = clamp((loadN or 0) / 4000, 0, 2.5)
  local dig = 1 + clamp((slip or 0) / 10, 0, 0.6)
  return k.soft * load * dig
end

function M.takes(kind, loadN, slip, cfg) return M.depth(kind, loadN, slip, cfg) >= cfg.minDepth end

-- a rut is as wide as the pressing: 0.5 to 0.9 of the material's width for light to heavy, wider with each pass
function M.width(baseWidth, depth, layer, cfg)
  return baseWidth * cfg.widthScale * (0.55 + 0.35 * clamp(depth, 0, 1.2) / 1.2) * (0.92 + 0.08 * (layer or 1))
end

-- ---- passes. The ground is counted in 1 m cells per surface kind; a chunk goes through cells, the deepest count says which layer this pass is.
function M.newGrid() return { cells = {}, n = 0 } end
local function key(x, y) return math.floor(x) * 131072 + math.floor(y) end

-- the layer (1..maxLayers+1) a new chunk over these points would be; maxLayers + 1 means the track is as deep as it gets (make nothing)
function M.layerFor(grid, kind, points, cfg)
  local most = 0
  for _, p in ipairs(points) do
    local c = grid.cells[kind .. ':' .. key(p[1], p[2])]
    if c and c > most then most = c end
  end
  return most + 1
end
function M.markPassed(grid, kind, points)
  local seen = {}                                                       -- a cell counts once per chunk, however many samples fall in it
  for _, p in ipairs(points) do
    local k = kind .. ':' .. key(p[1], p[2])
    if not seen[k] then
      seen[k] = true
      local c = grid.cells[k]
      if not c then grid.n = grid.n + 1 end
      grid.cells[k] = (c or 0) + 1
    end
  end
end
function M.forget(grid) grid.cells, grid.n = {}, 0 end

-- ---- chunks. A wheel's path is collected as samples { x, y, z }; `feed` adds one and returns the chunk when it is complete: enough samples, or the ground changed, or it jumped.
-- state = { kind, points = {}, last = {x,y} }
function M.newPath() return { kind = nil, points = {} } end

function M.feed(path, x, y, z, kind, cfg)
  local out
  local last = path.points[#path.points]
  if path.kind and (kind ~= path.kind or (last and (x - last[1]) ^ 2 + (y - last[2]) ^ 2 > 9)) then       -- the ground changed, or a jump of 3 m
    if #path.points >= 2 then out = { kind = path.kind, points = path.points } end
    path.points, path.kind = {}, nil
    last = nil
  end
  path.kind = kind
  if last and (x - last[1]) ^ 2 + (y - last[2]) ^ 2 < (cfg.step * 0.9) ^ 2 then return out end
  path.points[#path.points + 1] = { x, y, z }
  if #path.points >= cfg.chunkPoints and not out then
    out = { kind = path.kind, points = path.points }
    local tail = path.points[#path.points]
    path.points = { tail }                                              -- the next chunk starts where this one ended: no gap
  end
  return out
end

-- a path that has been quiet: whatever is collected is a chunk too (nil when there is too little)
function M.flush(path)
  local out
  if path.kind and #path.points >= 2 then out = { kind = path.kind, points = path.points } end
  path.points, path.kind = {}, nil
  return out
end

-- ---- the material: wet or dry with a little hysteresis (wasWet = the last answer for this track)
function M.material(kind, wet, wasWet, cfg)
  local isWet = wasWet
  if wet >= cfg.wetAbove then isWet = true elseif wet <= cfg.dryBelow then isWet = false end
  return 'csfx_rut_' .. kind .. (isWet and '_wet' or '_dry'), isWet
end

-- ---- the budget: chunks per second (a token bucket); returns true when one may be made now
function M.budget(state, dt, perSecond)
  state.tokens = math.min(perSecond, (state.tokens or perSecond) + dt * perSecond)
  if state.tokens >= 1 then state.tokens = state.tokens - 1 return true end
  return false
end

return M
