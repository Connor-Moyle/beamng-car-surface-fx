-- Car Surface FX: the rules of leaking fluids (oil, coolant, fuel, exhaust drips): what a car's damage and fluid state leak, how drips merge into puddles and how a puddle grows, fades and
-- takes grip from a tyre. Pure (no game calls), tested by tests/fluids_test.lua. Written fresh for Car Surface FX; the features follow Connor's Surface FX (drips, parked-car puddles, grip).
local M = {}

M.KINDS = { 'oil', 'coolant', 'fuel', 'exhaust' }
-- the game's own fluid-drop particle emitters (BNGP_<number>); the colour is baked into the emitter
M.DROP_PARTICLE = { oil = 36, coolant = 48, fuel = 50, exhaust = 50 }

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
M.clamp = clamp

-- the defaults, one table per fluid. size = the biggest a puddle gets (radius, m); growth = m^2 added per second of a full leak under a parked car; dripSize = a single drip's radius (m);
-- life = seconds a puddle lasts before it has dried (0 = it stays until recycled); grip = how much grip a tyre in the middle of a puddle loses (0..1); gripRadius = extra metres around the
-- puddle's edge where the loss fades out.
function M.defaults()
  return {
    enabled = true,
    texture = '',                                                -- the puddle picture: a file in art/decals/fluids ('' = any of them)
    meshes = true,                                               -- a puddle is a glossy plane like a rain puddle (fluidmesh.lua); off: flat decals only
    sheen = true,                                                -- oil carries a rainbow film
    gripEnabled = true,                                          -- the real physics part: a tyre in a puddle slips (proven by yaw logs under braking); the setting turns it off
    maxPuddles = 100,                                             -- ring size: the oldest are recycled
    cullRadius = 70,                                             -- puddles further than this from the camera are not drawn
    fallingDrops = true, dropSize = 0.06, dropCount = 2, maxDrops = 32,   -- the game's own drop particles from the leak (width m, drops per burst), and a cap on the drops followed to where they land
    stainSpeed = 3.0,                                            -- m/s: faster than this a leak leaves drip spots along the road instead of a puddle
    others = { enabled = false, maxCars = 4, range = 60 },       -- AI and traffic cars leak too (the nearest ones)
    kinds = {
      oil = { enabled = true, color = { 0.04, 0.035, 0.03 }, opacity = 0.80, size = 0.9, growth = 0.010, dripSize = 0.09, life = 0, grip = 0.85, gripRadius = 0.40 },
      coolant = { enabled = true, color = { 0.30, 0.78, 0.35 }, opacity = 0.55, size = 0.8, growth = 0.014, dripSize = 0.07, life = 900, grip = 0.65, gripRadius = 0.30 },
      fuel = { enabled = true, color = { 0.55, 0.45, 0.12 }, opacity = 0.40, size = 0.7, growth = 0.012, dripSize = 0.06, life = 420, grip = 0.70, gripRadius = 0.30 },
      exhaust = { enabled = false, color = { 0.10, 0.10, 0.10 }, opacity = 0.35, size = 0.25, growth = 0.002, dripSize = 0.04, life = 240, grip = 0.0, gripRadius = 0 },
    },
  }
end

-- ---- what the car leaks. report = what the car side read: { oilPan, oilCooler, radiator, overheating, oilRate, coolantRate (kg/s, the engine's own fluid state), fuelRate, fuelStored,
-- cold, running } (booleans / numbers, nil = not known). The engine's leak rates (kg/s) win over the damage flags: a hole in the oil pan that has lost its oil leaks no more.
-- -> { oil, coolant, fuel, exhaust } each 0..1 (0 = not leaking)
M.RATE_FULL = 0.3                                                -- kg/s that counts as a full leak
function M.leaks(r)
  r = r or {}
  local out = { oil = 0, coolant = 0, fuel = 0, exhaust = 0 }
  if r.oilRate ~= nil then
    if r.oilRate > 0.0005 then out.oil = clamp(0.25 + r.oilRate / M.RATE_FULL * 0.75, 0.25, 1) end
  elseif r.oilPan then out.oil = 1 elseif r.oilCooler then out.oil = 0.7 end
  if r.coolantRate ~= nil then
    if r.coolantRate > 0.0005 then out.coolant = clamp(0.25 + r.coolantRate / M.RATE_FULL * 0.75, 0.25, 1) end
  elseif r.radiator then out.coolant = 1 elseif r.overheating then out.coolant = 0.5 end
  if (r.fuelRate or 0) > 0 and (r.fuelStored or 1) > 0 then out.fuel = clamp(0.35 + (r.fuelRate or 0) * 0.5, 0.35, 1) end
  if r.running and r.cold then out.exhaust = 0.4 end                 -- a cold engine condenses water in the exhaust
  return out
end

-- how many drips a leak of intensity i makes in dt seconds (the fraction carries over as `carry`): about 4 a second at full
M.DRIPS_PER_SECOND = 4
function M.drips(intensity, dt, carry)
  local x = (carry or 0) + (intensity or 0) * M.DRIPS_PER_SECOND * (dt or 0)
  local n = math.floor(x)
  return n, x - n
end

-- ---- a falling drop: { x, y, z, vz, gz (the ground), kind, amount, speed }; falls under gravity from where it left the car. Returns true when it has hit the ground.
M.GRAVITY = 9.81
function M.fallStep(d, dt)
  d.vz = d.vz - M.GRAVITY * dt
  d.z = d.z + d.vz * dt
  if d.z <= d.gz then d.z = d.gz return true end
  return false
end

-- ---- puddles. A store is a ring: { list = {}, head = 0, count = 0, max = n }
function M.newStore(max) return { list = {}, head = 0, count = 0, max = math.max(4, math.floor(max or 60)) } end

local function area(r) return math.pi * r * r end
local function radiusOf(a) return math.sqrt(a / math.pi) end

-- one drip of `kind` lands at x, y, z. stain: a spot on the road from a moving car (never merges); else it feeds the nearest puddle of its kind within reach, or starts one.
-- amount: how much (1 = a normal drip). Returns the puddle.
function M.drip(store, x, y, z, kind, amount, cfg, stain, seed)
  local k = cfg.kinds[kind]
  if not k or not k.enabled then return nil end
  amount = amount or 1
  if not stain then
    local best, bd = nil, 1e9
    for i = 1, store.count do
      local p = store.list[i]
      if p and p.kind == kind and not p.stain then
        local dx, dy = p.x - x, p.y - y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < p.r + 0.35 and d < bd then best, bd = p, d end
      end
    end
    if best then
      local a = area(best.r) + k.growth * 0.25 * amount            -- a drip adds a quarter second's worth of leak
      best.r = math.min(k.size, radiusOf(a))
      best.age = 0
      best.x, best.y = best.x + (x - best.x) * 0.05, best.y + (y - best.y) * 0.05   -- the puddle creeps toward where it is fed
      return best
    end
  end
  local i = (store.head % store.max) + 1
  local p = store.list[i] or {}
  p.gen, p.meshed = (p.gen or 0) + 1, nil                              -- a new puddle in a recycled slot: its plane (fluidmesh) is not the old one's
  p.x, p.y, p.z, p.kind, p.r, p.age, p.stain = x, y, z, kind, k.dripSize * (stain and (0.7 + 0.6 * ((seed or 0.5))) or 1), 0, stain and true or false
  p.angle = (seed or 0.5) * 6.2832
  p.seed = seed or 0.5
  p.variant = 1 + math.floor((seed or 0.5) * 3) % 3
  store.list[i], store.head = p, i
  if store.count < store.max then store.count = store.count + 1 end
  return p
end

-- time passes: puddles with a life dry up (r shrinks to nothing in the last fifth of it), a puddle that has dried is dropped from the list. Returns how many are left.
function M.age(store, dt, cfg)
  local alive = 0
  for i = 1, store.count do
    local p = store.list[i]
    if p and p.r > 0 then
      local k = cfg.kinds[p.kind]
      p.age = (p.age or 0) + dt
      if k and k.life > 0 and p.age > k.life then p.r = 0 else alive = alive + 1 end
    end
  end
  return alive
end

-- the ring recycles the oldest next: once it is full, the oldest tenth fades out by rank (0 = gone, 1 = untouched) so a recycled puddle does not pop
function M.ringFade(store, i)
  if store.count < store.max then return 1 end
  local zone = math.max(1, math.ceil(store.max * 0.1))
  local rank = (i - store.head - 1) % store.max + 1                   -- 1 = the oldest, next to be overwritten
  return rank > zone and 1 or (rank - 0.5) / zone
end

-- how opaque a puddle is: its fluid's opacity, thinner while it dries
function M.alpha(p, cfg)
  local k = cfg.kinds[p.kind]
  if not k then return 0 end
  local a = k.opacity
  if k.life > 0 then
    local left = 1 - (p.age or 0) / k.life
    if left < 0.3 then a = a * clamp(left / 0.3, 0, 1) end
  end
  if p.stain then a = a * 0.8 end
  return a
end

-- ---- grip. The multiplier (0..1, 1 = full grip) a tyre at x, y gets from the puddles: inside a puddle it loses `grip` of its grip, fading out over `gripRadius` outside the edge.
-- Stains are too small to matter. The worst puddle wins.
function M.gripAt(store, x, y, cfg)
  local mult = 1
  for i = 1, store.count do
    local p = store.list[i]
    if p and p.r > 0.15 then
      local k = cfg.kinds[p.kind]
      if k and k.enabled and k.grip > 0 then
        local dx, dy = p.x - x, p.y - y
        local d = math.sqrt(dx * dx + dy * dy)
        local reach = p.r + (k.gripRadius or 0)
        if d < reach then
          local f = d <= p.r and 1 or 1 - (d - p.r) / math.max(0.01, k.gripRadius)
          local m = 1 - k.grip * f
          if m < mult then mult = m end
        end
      end
    end
  end
  return mult
end

-- the puddles near a car, as the short list the car side gets: { {x, y, r, grip, radius}, ... } nearest first, at most n
function M.near(store, x, y, range, cfg, n)
  local out = {}
  local r2 = range * range
  for i = 1, store.count do
    local p = store.list[i]
    if p and p.r > 0.15 then
      local k = cfg.kinds[p.kind]
      if k and k.enabled and k.grip > 0 then
        local dx, dy = p.x - x, p.y - y
        local d2 = dx * dx + dy * dy
        if d2 <= r2 then out[#out + 1] = { d2, p, k } end
      end
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  local list = {}
  for i = 1, math.min(#out, n or 6) do
    local p, k = out[i][2], out[i][3]
    list[i] = { p.x, p.y, p.r, k.grip, k.gripRadius or 0 }
  end
  return list
end

-- the same maths on that short list (the car side has no store): used by the car side and by the tests so the two cannot drift apart
function M.gripFromList(list, x, y)
  local mult = 1
  for _, e in ipairs(list or {}) do
    local dx, dy = e[1] - x, e[2] - y
    local d = math.sqrt(dx * dx + dy * dy)
    local r, grip, gr = e[3], e[4], e[5]
    if d < r + gr then
      local f = d <= r and 1 or 1 - (d - r) / math.max(0.01, gr)
      local m = 1 - grip * f
      if m < mult then mult = m end
    end
  end
  return mult
end

-- smoothing on the car side: grip drops fast when a tyre enters a puddle and comes back slower
function M.smooth(cur, target, dt)
  local rate = target < cur and 6.0 or 1.2
  local step = rate * (dt or 0)
  if cur < target then return math.min(cur + step, target) end
  return math.max(cur - step, target)
end

return M
