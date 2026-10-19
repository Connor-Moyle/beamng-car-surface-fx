-- Car Surface FX: the rules of ruts (port P4, written fresh): which ground takes a rut, how deep a wheel presses it (the ground's softness x the wheel's load, a spinning wheel digs),
-- how repeated passes along the same track deepen it, and how the wheel path is cut into chunks. Pure (no game calls), tested by tests/ruts_test.lua.
local M = {}

local hollowrules = require('carSurfaceFx/hollowrules')

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
    hollows = hollowrules.defaults(),                                  -- visual terrain hollows under the wheels (hollows.lua); off until seen in game
    tracks = { enabled = false, maxRoads = 150, step = 0.5, chunkPoints = 5, widthScale = 0.5 },            -- the faint tyre tracks on soft ground as lit road decals (ruts.trackSegment, from marks.lua)
    gouges = { enabled = false, step = 0.3, chunkPoints = 4, minForce = 400, widthMin = 0.25, widthMax = 0.7 },      -- the body scraping the ground (ruts.gouge, from the body wear hits)
    berms = { enabled = false, maxBerms = 120, heightScale = 1.0, lift = 0.01 },      -- soil lips beside the track (berm.lua, bermrules.lua); off until seen in game
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

-- ---- gouges: a body panel dragged over the ground. The ground is tarmac (a scrape: gouge_asphalt) or soft (gouge_dirt); anything else leaves nothing.
M.GOUGE_GROUND = { tarmac = 'asphalt', dirt = 'dirt', sand = 'dirt', gravel = 'dirt', mud = 'dirt', grass = 'dirt', snow = 'dirt' }
function M.gougeKind(surface) return M.GOUGE_GROUND[surface] end
-- the gouge's width for a force in N: wider with a harder hit
function M.gougeWidth(force, g) return clamp(g.widthMin + (g.widthMax - g.widthMin) * clamp((force or 0) / 6000, 0, 1), g.widthMin, g.widthMax) end
function M.gougeMaterial(kind, wet, wasWet, cfg)
  local isWet = wasWet
  if wet >= cfg.wetAbove then isWet = true elseif wet <= cfg.dryBelow then isWet = false end
  return 'csfx_gouge_' .. kind .. (isWet and '_wet' or '_dry'), isWet
end

-- ---- tracks: marks.lua sends one short segment per wheel step; here they are joined into paths (a segment that starts where an open path ends continues it) and cut into chunks.
M.TRACK_KINDS = { mud = true, snow = true, sand = true, dirt = true, gravel = true }          -- the grounds that have a lit track material (csfx_track_<kind>_dry / _wet)
local CHAINS, JOIN = 8, 0.15
function M.newChains() return { list = {} } end
-- one segment a -> b over the ground `kind` at time `now`: returns a chunk { kind, points, track = true } when a path is long enough, else nil
function M.chain(ch, kind, ax, ay, az, bx, by, bz, now, cfg)
  local c
  for _, o in ipairs(ch.list) do
    if o.kind == kind and (o.ex - ax) ^ 2 + (o.ey - ay) ^ 2 <= JOIN * JOIN then c = o break end
  end
  if not c then
    c = { kind = kind, points = { { ax, ay, az } }, ex = ax, ey = ay }
    ch.list[#ch.list + 1] = c
    if #ch.list > CHAINS then table.remove(ch.list, 1) end
  end
  c.ex, c.ey, c.at = bx, by, now
  local last = c.points[#c.points]
  if (bx - last[1]) ^ 2 + (by - last[2]) ^ 2 < (cfg.step * 0.9) ^ 2 then return nil end
  c.points[#c.points + 1] = { bx, by, bz }
  if #c.points >= cfg.chunkPoints then
    local out = { kind = kind, points = c.points, track = true }
    c.points = { { bx, by, bz } }                                        -- the next chunk starts where this one ended
    return out
  end
end
-- paths quiet for `idle` seconds end: their points are chunks too (when there are two or more)
function M.chainFlush(ch, now, idle)
  local out, keep = {}, {}
  for _, c in ipairs(ch.list) do
    if now - (c.at or now) >= idle then
      if #c.points >= 2 then out[#out + 1] = { kind = c.kind, points = c.points, track = true } end
    else keep[#keep + 1] = c end
  end
  ch.list = keep
  return out
end
function M.trackMaterial(kind, wet, wasWet, cfg)
  local isWet = wasWet
  if wet >= cfg.wetAbove then isWet = true elseif wet <= cfg.dryBelow then isWet = false end
  return 'csfx_track_' .. kind .. (isWet and '_wet' or '_dry'), isWet
end

-- ---- the budget: chunks per second (a token bucket). refill adds the time's tokens (never spends); budget(state) returns true and spends one when a chunk may be made now.
function M.refill(state, dt, perSecond)
  state.tokens = math.min(perSecond, (state.tokens or perSecond) + dt * perSecond)
end
function M.budget(state, dt, perSecond)
  M.refill(state, dt, perSecond)
  if state.tokens >= 1 then state.tokens = state.tokens - 1 return true end
  return false
end

return M
