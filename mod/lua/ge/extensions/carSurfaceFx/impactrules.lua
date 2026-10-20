-- Car Surface FX: the rules of crashes (port P9-P11): which breaks are windows, which materials make which debris, which contacts throw sparks, and how a flying chip or a spark moves.
-- Pure (no game calls), tested by tests/impacts_test.lua. Written fresh for Car Surface FX; the features follow Connor's Surface FX (shard piles, debris, sparks).
-- The material ids are the game's particles.json node materials: metal 2, plastic 3, rubber 4, glass 5, wood 6, foliage 7, cloth 8, water 9, rock 13, the dirt family 14-19, grass 20,
-- snow 22, thin foliage 31.
local M = {}

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
M.clamp = clamp

M.MAT = { METAL = 2, PLASTIC = 3, RUBBER = 4, GLASS = 5, WOOD = 6, ROCK = 13 }
M.DEBRIS = { 'metal', 'bolt', 'plastic', 'glass', 'wood', 'rock' }
-- the game's own particle emitters (BNGP_<number>, lua/common/particles.json and vehicle/beamstate.lua): plastic chunks 56-58 and glass 68/69 are what it throws itself when a plastic or glass
-- beam breaks, wood 12, loose stones 2, and 1 is the bright fleck its collision table uses for metal on asphalt and metal on metal (the sparks). Their colours are baked into the emitters.
M.PARTICLE = { metal = { 1 }, bolt = { 1 }, plastic = { 56, 57, 58 }, glass = { 68, 69 }, wood = { 12 }, rock = { 2 } }
M.SPARK_PARTICLE = 1
function M.particleFor(kind, rnd)
  local list = M.PARTICLE[kind] or M.PARTICLE.metal
  return list[1 + math.floor((rnd or 0) * #list) % #list]
end

function M.defaults()
  return {
    enabled = true,
    others = { enabled = false, maxCars = 4, range = 60 },
    glass = {
      enabled = true, texture = '', color = { 0.92, 0.96, 1.0 }, opacity = 0.95, size = 1.0, maxPiles = 40, minEnergy = 5, clusterRadius = 0.8, idle = 0.22,
    },
    debris = {
      enabled = true, texture = '', particles = true, amount = 1.0, impactSpeed = 6.0, jointChance = 0.5, maxFlying = 60, maxResting = 120, life = 180, clearDistance = 250, bounce = 0.35, friction = 0.55,
      size = 1.0, boltChance = 0.3,
      colors = { metal = { 0.45, 0.45, 0.47 }, bolt = { 0.30, 0.30, 0.32 }, plastic = { 0.12, 0.12, 0.13 }, glass = { 0.78, 0.86, 0.90 }, wood = { 0.40, 0.28, 0.16 }, rock = { 0.42, 0.40, 0.38 } },
    },
    sparks = { enabled = true, amount = 1.0, minSpeed = 3.0, minForce = 600 },
    cullRadius = 90,
  }
end

-- ---- glass. A window is a beam with a deform or break group that says glass (a name holding glass / window / windshield / windscreen: roofglass_break, windshield_break), or a glass node
-- material on a grouped beam. Not wood or plastic lenses, and not lamp glass (headlightglass_L_break and the like are lamps). Drive shafts have groups too, and say none of this.
-- beamInfo = { deformGroup, breakGroup }, m1 / m2 = the node materials of its two nodes.
function M.isGlassBeam(beamInfo, m1, m2)
  if not (beamInfo and (beamInfo.deformGroup or beamInfo.breakGroup)) then return false end
  local mats = M.MAT
  if m1 == mats.WOOD or m2 == mats.WOOD or m1 == mats.PLASTIC or m2 == mats.PLASTIC then return false end
  local g = (tostring(beamInfo.deformGroup or '') .. ' ' .. tostring(beamInfo.breakGroup or '')):lower()
  if g:find('light', 1, true) or g:find('lamp', 1, true) then return false end
  if m1 == mats.GLASS or m2 == mats.GLASS then return true end
  return g:find('glass', 1, true) ~= nil or g:find('window', 1, true) ~= nil or g:find('windshield', 1, true) ~= nil or g:find('windscreen', 1, true) ~= nil
end

-- a pane is many beams: nearby breaks fold into one cluster {x,y,z (sums), n, last}; returns the cluster list (modified in place)
function M.addBreak(clusters, x, y, z, now, radius, max)
  local r2 = radius * radius
  for _, c in ipairs(clusters) do
    local dx, dy, dz = x - c.x / c.n, y - c.y / c.n, z - c.z / c.n
    if dx * dx + dy * dy + dz * dz < r2 then
      c.x, c.y, c.z, c.n, c.last = c.x + x, c.y + y, c.z + z, c.n + 1, now
      return true
    end
  end
  if #clusters >= (max or 12) then return false end
  clusters[#clusters + 1] = { x = x, y = y, z = z, n = 1, last = now }
  return true
end

-- the clusters that have gone quiet: removed from the list and returned as { x, y, z, severity 0.3..1 }
function M.flush(clusters, now, idle)
  local out = {}
  local i = 1
  while i <= #clusters do
    local c = clusters[i]
    if now - c.last >= idle then
      out[#out + 1] = { x = c.x / c.n, y = c.y / c.n, z = c.z / c.n, sev = c.n >= 20 and 1 or 0.3 + 0.7 * (c.n / 20) }
      table.remove(clusters, i)
    else
      i = i + 1
    end
  end
  return out
end

-- the radius of a shard pile from the severity (a small side window to a windscreen), and how many shards it is drawn with
function M.pileRadius(sev, sizeScale) return (0.4 + 1.0 * clamp(sev, 0, 1)) * (sizeScale or 1) end

-- ---- debris. A broken joint or a hard hit: which kind of piece (nil = none: tyres leave nothing). rnd = a number 0..1
function M.classify(m1, m2, rnd, boltChance)
  local mats = M.MAT
  if m1 == mats.RUBBER or m2 == mats.RUBBER then return nil end
  if m1 == mats.GLASS or m2 == mats.GLASS then return 'glass' end
  if m1 == mats.WOOD or m2 == mats.WOOD then return 'wood' end
  if m1 == mats.ROCK or m2 == mats.ROCK then return 'rock' end
  if m1 == mats.PLASTIC or m2 == mats.PLASTIC then return 'plastic' end
  if (rnd or 1) < (boltChance or 0.3) then return 'bolt' end
  return 'metal'
end

-- how many pieces a burst makes: glass a handful, the rest one or two, times the setting
function M.pieces(kind, hard, cfg)
  local base = kind == 'glass' and 8 or (hard and 2 or 1)
  return math.max(0, math.floor(base * (cfg.amount or 1) + 0.5))
end

-- a piece in the air: { x,y,z, vx,vy,vz, kind, size, spin, rest }; one step with gravity; hitting the ground (gz) it bounces and slides, and rests when slow. Returns true when it came to rest.
M.GRAVITY = 9.81
function M.step(p, dt, gz, bounce, friction)
  if p.rest then return true end
  p.vz = p.vz - M.GRAVITY * dt
  p.x, p.y, p.z = p.x + p.vx * dt, p.y + p.vy * dt, p.z + p.vz * dt
  if p.z <= gz then
    p.z = gz
    if p.vz < 0 then p.vz = -p.vz * bounce end
    local f = clamp(1 - friction * dt * 8, 0, 1)
    p.vx, p.vy = p.vx * f, p.vy * f
    if p.vz < 0.8 and p.vx * p.vx + p.vy * p.vy < 0.25 then p.rest, p.vz, p.vx, p.vy = true, 0, 0, 0 end
  end
  return p.rest == true
end

-- ---- sparks. Metal against a hard surface, sliding: not on soft or loose ground, not on rubber
local NO_SPARK = { [4] = true, [7] = true, [8] = true, [9] = true, [14] = true, [15] = true, [16] = true, [17] = true, [18] = true, [19] = true, [20] = true, [22] = true, [31] = true }
function M.sparkOk(m1, m2, force, slip, cfg)
  if (force or 0) < cfg.minForce or (slip or 0) < cfg.minSpeed then return false end
  if m1 ~= M.MAT.METAL and m2 ~= M.MAT.METAL then return false end
  if NO_SPARK[m1] or NO_SPARK[m2] then return false end
  return true
end

-- the sparks of a grinding contact: count scaled by the setting and the force, given the car's velocity and the surface normal-ish spread
function M.sparkCount(force, cfg) return math.max(1, math.floor((1 + math.min(force or 0, 6000) / 2000) * (cfg.amount or 1) + 0.5)) end

return M
