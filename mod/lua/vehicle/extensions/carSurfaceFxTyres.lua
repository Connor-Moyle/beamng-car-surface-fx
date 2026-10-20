-- Car Surface FX, vehicle side: tyre wear, temperature and grip (rules: csfx_tyrerules, research: docs/TYRE_WEAR_RESEARCH.md in the control repo).
-- Per wheel, every frame, the slip power of the wheel (slip speed x load) is credited to the tread node that touches the ground (and the other lane of its sector); ten times a
-- second the energy wears the tread, heats the tyre and sets the grip of every tread node (obj:setNodeFrictionSlidingCoefs, the call the game's own deflation uses) from the
-- node's own stock friction. This module is the only writer of tread friction on the car: other modules (the fluids) give it their multiplier with setExternal.
local R = require('csfx_tyrerules')
local M = {}
local abs, max, min = math.abs, math.max, math.min

local TICK = 0.1                    -- seconds between wear / temperature / grip steps
local REPORT = 0.5                  -- seconds between reports to the game side
local MIN_DOWNFORCE = 200           -- N: a wheel in the air or barely touching wears nothing
local DEBRIS_FLUSH_G = 1             -- grams of rubber worn off before one debris event goes to the game side
local LOCK_RATIO = 0.3                -- wheel surface speed under this share of the slip speed counts as locked
local APPLY_EPS = 0.005             -- a change under 0.5 % is not worth the call
local SPARK_SLIP = 2.5               -- m/s of slip over which belts or a bare rim throw sparks (the engine's own METAL on asphalt rule uses 2.5 too)
local SPARK_MAX = 4                  -- sparks per tick (10 Hz) at the most
local SPARK_PARTICLE = 1            -- particles.json type 1: sparks
local RUBBER_MAT = 4            -- the tyre's own material id; the ground is the other one (as in carSurfaceFxWheels)
local REAPPLY_FRAMES = 2            -- after a reset the engine restores its own friction first (our onReset runs before its resets): write again two frames later

local cfg = R.defaults()
local fitAxle = {}                  -- axle ('front' / 'rear') -> a compound fitted to that axle alone (staggered setups)
local compound = nil                -- nil: every tyre keeps its stock class (what the car's own friction already is); a name fits that compound on all of them
local env = { wet = 0, water = 0, surface = 'asphalt', ambient = nil, road = nil }
local tyres = nil                   -- wheel index -> { t = rules tyre, wd, cids = {j -> cid}, slotOf = {cid -> j}, base = {j -> {fc, sfc}}, applied = {j -> factor}, pNom }
local external = {}                 -- kind -> { wheel index -> multiplier }
local surfaceOf = {}                 -- collision material id -> surface key of the rules (the game side sends it from the level's ground models)
local pendingBlob = nil             -- a saved state waiting for the tyres to be built
local timer, report, reapply = 0, 0, 0
local enabled = false
local failed

-- the class of the stock tyre, from the numbers of its jbeam (research 7.1: a standard tyre has noLoadCoef 1.35 and treadCoef 0.7, a race tyre 2.07 and 0). Starting values to tune in game.
local function classify(wd)
  local nl, tc, r = tonumber(wd.noLoadCoef) or 1.35, tonumber(wd.treadCoef) or 0.7, tonumber(wd.radius) or 0.3
  if nl >= 2.5 then return 'drag' end
  if nl >= 1.9 and tc < 0.2 then return 'semislick' end
  if r >= 0.38 and tc >= 0.9 then return 'offroad' end
  return 'road'
end
M.classify = classify

-- the axle of a wheel from the car's own name (FL, FR, RL, RR), and the compound fitted to it: an axle's set, else the whole car's, else nil (the stock class)
local function axleOf(wd)
  local c = tostring(wd.name or ''):upper():sub(1, 1)
  return c == 'F' and 'front' or (c == 'R' and 'rear' or nil)
end
local function fittedTo(wd) return fitAxle[axleOf(wd) or ''] or compound end

local WATER_DEEP = 0.7              -- aquaplaning depth (0..1) of a wheel whose HUB is under water (the game's own water check, wheels.lua uses the same node)
local WATER_SHALLOW = 0.3           -- of a wheel whose contact patch is under water but not its hub: a flooded road, a ford. The car cannot see a puddle's depth, only whether the water covers a node
local function groundOf(wd)         -- the ground under a wheel: its contact material that is not the rubber, looked up in the table the game side sent (setSurfaces)
  local id = tonumber(wd.contactMaterialID1) or -1
  if id == RUBBER_MAT then id = tonumber(wd.contactMaterialID2) or -1 end
  return surfaceOf[id]
end

local function pcalls(f, ...) local ok, a = pcall(f, ...) return ok and a or nil end

local function ambientC()
  if env.ambient then return env.ambient end
  local k = obj.getEnvTemperature and pcalls(obj.getEnvTemperature, obj)
  return k and (k - 273.15) or 20
end

local function pressureOf(wd)
  if not (obj.getGroupPressure and wd.pressureGroupId) then return nil end
  return pcalls(obj.getGroupPressure, obj, wd.pressureGroupId)
end

local function build()
  if tyres or not (wheels and wheels.wheels and next(wheels.wheels) and v and v.data and v.data.nodes) then return end
  tyres = {}
  for wi, wd in pairs(wheels.wheels) do
    local tn = wd.treadNodes
    if tn and #tn >= 16 and #tn % 2 == 0 then
      local e = { wd = wd, cids = {}, slotOf = {}, base = {}, applied = {} }
      local ok = true
      for j, cid in ipairs(tn) do
        local nd = v.data.nodes[cid]
        if not (nd and nd.frictionCoef) then ok = false break end
        e.cids[j], e.slotOf[cid] = cid, j
        e.base[j] = { nd.frictionCoef, nd.slidingFrictionCoef or nd.frictionCoef }
      end
      if ok then
        e.stock = classify(wd)
        e.t = R.new(fittedTo(wd) or e.stock, #tn / 2, tonumber(wd.radius), tonumber(wd.tireWidth), ambientC())
        e.ratio = R.swapRatio(e.stock, e.t.compound)     -- the stock friction already is the stock class: a slick on a road jbeam gains, a road tyre on a slick jbeam loses
        e.pNom = pressureOf(wd)
        tyres[wi] = e
      end
    end
  end
  if pendingBlob then
    for wi, blob in pairs(pendingBlob) do local k = tonumber(wi) if tyres[k] then R.restore(tyres[k].t, blob) end end
    pendingBlob = nil
  end
end

local function extMult(wi)
  local m = 1
  for _, byWheel in pairs(external) do m = m * (byWheel[wi] or 1) end
  return m
end

-- write the grip of every tread node of one tyre: stock friction x the rules x the external multipliers. Never on a deflated tyre (the game owns those nodes then).
local function applyGrip(wi, e, force)
  if e.wd.isTireDeflated then e.applied = {} return end
  local t, ext = e.t, extMult(wi)
  local ctx = { water = max(env.water, e.water or 0), v = abs(tonumber(e.wd.wheelSpeed) or 0), surface = e.surface or env.surface }
  local wet = max(env.wet, e.surface == 'wet' and 1 or 0)
  for j = 1, 2 * t.n do
    local fs, fk = R.nodeGrip(t, j, wet, cfg, ctx)
    fs, fk = fs * e.ratio, fk * e.ratio
    local f = (fs + fk) * 0.5 * ext          -- (one factor per node: the rules give equal static and sliding multipliers)
    local last = e.applied[j]
    if force or not last or abs(f - last) > APPLY_EPS * last then
      local b = e.base[j]
      pcall(function() obj:setNodeFrictionSlidingCoefs(e.cids[j], b[1] * fs * ext, b[2] * fk * ext) end)
      e.applied[j] = f
    end
  end
end

local function credit(e, dt)
  local wd, t = e.wd, e.t
  if e.wd.isTireDeflated or t.blown then return 0 end
  local fz = tonumber(wd.downForce) or 0
  if fz < MIN_DOWNFORCE then return 0 end
  local p = R.slipPower(abs(tonumber(wd.lastSlip) or 0), fz, 1, cfg.deadZone)
  if p <= 0 then return 0 end
  local j = e.slotOf[wd.lastTreadContactNode]
  if not j then return p end                       -- (power still heats the tyre, no node to wear)
  local mate = j % 2 == 1 and j + 1 or j - 1       -- the other lane of the sector
  local slip = abs(tonumber(wd.lastSlip) or 0)
  local lock = abs(tonumber(wd.wheelSpeed) or 0) < LOCK_RATIO * slip       -- the wheel barely turns while the ground goes by: locked sliding (low flat-spot wear)
  R.addEnergy(t, j, p * dt * 0.5, lock)
  R.addEnergy(t, mate, p * dt * 0.5, lock)
  return p
end

local powerSum = {}                                -- wheel index -> W integrated over the tick (J)

local function tick(dt)
  local events
  for wi, e in pairs(tyres) do
    local wd, t = e.wd, e.t
    if not wd.isTireDeflated then
      local pr = pressureOf(wd)
      e.surface = groundOf(wd) or e.surface                         -- (kept while the wheel is in the air)
      e.water = 0
      if (tonumber(wd.downForce) or 0) >= MIN_DOWNFORCE then
        local contact = e.cids[e.slotOf[wd.lastTreadContactNode] or 1]
        if wd.node1 and pcalls(obj.inWater, obj, wd.node1) then e.water = WATER_DEEP
        elseif contact and pcalls(obj.inWater, obj, contact) then e.water = WATER_SHALLOW end
      end
      local wetNow = env.wet > 0.3 or e.surface == 'wet' or max(env.water, e.water) > 0
      local ctx = { surface = e.surface or env.surface, wet = wetNow, pressure = pr, pNom = e.pNom }
      R.wearStep(t, ctx, cfg)
      local dg, dT = R.takeDebris(t, cfg)
      e.debrisG = (e.debrisG or 0) + dg
      if e.debrisG >= DEBRIS_FLUSH_G then events = events or {} events[#events + 1] = { wi, 'debris', e.debrisG, dT } e.debrisG = 0 end
      R.tempStep(t, { dt = dt, power = (powerSum[wi] or 0) / dt, v = abs(tonumber(wd.wheelSpeed) or 0), fz = tonumber(wd.downForce) or 0, ambient = ambientC(),
        road = env.road, wet = env.wet, brake = tonumber(wd.brakeSurfaceTemperature), pressure = pr, pNom = e.pNom }, cfg)
      local ev = R.fireStep(t, dt, env.wet, cfg)
      if ev then
        events = events or {} events[#events + 1] = { wi, ev }
        if ev == 'ignite' then if cfg.fireSpread then pcall(M.lightTyre, wi) end elseif ev == 'out' or ev == 'pop' then pcall(M.putOut, wi)
        elseif ev == 'spread' and cfg.fireSpread then pcall(M.igniteNearest, wi) end
      end
      if t.fire and not e.fireCid then                            -- without the game's fire (spread off): our own flames and smoke on the tread, nothing that can heat the car
        pcall(function()
          local cid = e.cids[e.slotOf[wd.lastTreadContactNode] or 1]
          obj:addParticleByNodesRelative(cid, wd.node1, -1, 29, 0, 1)
          obj:addParticleByNodesRelative(cid, wd.node1, -1, 52, 0, 1)
        end)
      end
      local lvl = R.smoke(t.Ts, cfg)                              -- smoke of a burnout (probe f2: particle 51, 52 when hotter): one puff per tick, more often the hotter
      if lvl > 0 and not t.blown and math.random() < lvl then pcall(function() obj:addParticleByNodesRelative(e.cids[e.slotOf[wd.lastTreadContactNode] or 1], wd.node1, -1, lvl >= 0.8 and 52 or 51, 0, 1) end) end
      if (t.blown or R.stage(t, cfg) >= 5) and (tonumber(wd.lastSlip) or 0) > SPARK_SLIP and (tonumber(wd.downForce) or 0) >= MIN_DOWNFORCE then   -- belts (or the rim) sliding: sparks at the contact patch
        local n = min(SPARK_MAX, 1 + math.floor(((tonumber(wd.lastSlip) or 0) - SPARK_SLIP) / 3))
        if not e.sparked then e.sparked = true obj:queueGameEngineLua(string.format('if carSurfaceFx_tyres then carSurfaceFx_tyres.lookEvent(%d,%d,"sparks",%.1f) end', obj:getId(), wi, tonumber(wd.lastSlip) or 0)) end   -- once per wheel: the proof in beamng.log
        pcall(function() local cid = e.cids[e.slotOf[wd.lastTreadContactNode] or 1] for _ = 1, n do obj:addParticleByNodesRelative(cid, wd.node1, -1, SPARK_PARTICLE, 0, 1) end end)
      end
      if t.blown and not wd.isPunctured and wheels.deflateTire then pcall(wheels.deflateTire, wd.wheelID or wi) end
    end
    R.clearEnergy(t)
    powerSum[wi] = 0
    applyGrip(wi, e, false)
  end
  return events
end

-- the flat-spot shake of a wheel: how often it comes round (Hz), and the radial force (N) the worst flat spot pulls on the tyre (the game side shakes the camera / the wheel with it)
function M.shake(wi)
  local e = tyres and tyres[wi]
  if not e or e.wd.isTireDeflated then return 0, 0 end
  local d = R.worstFlat(e.t)
  if d < cfg.flat.minDepth then return 0, 0 end
  return R.shakeHz(tonumber(e.wd.angularVelocity) and (tonumber(e.wd.angularVelocity) * e.t.r) or tonumber(e.wd.wheelSpeed), e.t.r), R.shakeForce(d)
end

local function sendState(events)
  local parts = {}
  for wi, e in pairs(tyres) do
    local worst = R.worstFlat(e.t)
    local hz, sn = M.shake(wi)
    local stage = e.t.blown and 5 or R.stage(e.t, cfg)
    if carSurfaceFxTyreLook then pcall(carSurfaceFxTyreLook.set, wi, (cfg.look and cfg.look.enabled == false) and 0 or stage, true) end      -- (the look switch off: the car's own tyre material)
    local minH = math.huge
    for j = 1, 2 * e.t.n do minH = min(minH, e.t.h[j]) end
    minH = max(0, minH)                                         -- below 0 the tread is into the belts (cord margin): reported as 0
    parts[#parts + 1] = string.format('{%d,%d,%.1f,%.1f,%.2f,%s,%s,%.1f,%.0f,%.2f,%.2f,%q,%q}', wi, stage, e.t.Ts, e.t.Tc, worst, tostring(e.t.blown), tostring(e.t.fire ~= nil), hz, sn,
      minH, e.t.c.h0, e.t.compound, tostring(e.wd.name or ''))
  end
  local ev = {}
  for _, x in ipairs(events or {}) do ev[#ev + 1] = x[3] and string.format('{%d,%q,%.2f,%.0f}', x[1], x[2], x[3], x[4] or 0) or string.format('{%d,%q}', x[1], x[2]) end
  obj:queueGameEngineLua(string.format('if carSurfaceFx_tyres then carSurfaceFx_tyres.state(%d,{%s},{%s}) end', obj:getId(), table.concat(parts, ','), table.concat(ev, ',')))
end

-- ---- visuals, thrown with the game's own particles from the tread node of a wheel, away from its hub (so the plume starts at the tyre, not above it)
local SMOKE_SMALL, SMOKE_MEDIUM, CHUNK = 51, 52, 56      -- BNGP_<n> of lua/vehicle/fire.lua; the chunk is the game's plastic piece (the colour is baked in the emitter)
local smoke, smokeT = {}, 0                                 -- wheel index -> level 0..1
local function treadNode(wi) local e = tyres and tyres[wi] return e and e.wd.node1, e and e.wd.node2 end
function M.fx(kind, wi, a)
  local n, hub = treadNode(wi)
  if not (n and hub) then return false end
  if kind == 'smoke' then smoke[wi] = (tonumber(a) or 0) > 0 and a or nil return true end
  if kind == 'debris' or kind == 'pop' then
    local v3 = obj:getNodeVelocityVector(n)
    pcall(function() obj:addParticleVelWidthTypeCount(n, vec3(0, 0, 1), v3, 2.0, 0.15, CHUNK, kind == 'pop' and 6 or math.max(1, math.min(4, math.floor((tonumber(a) or 5) / 5)))) end)
    return true
  end
  return false
end
local function smokeFrame(dt)
  smokeT = smokeT + dt
  if smokeT < 0.1 then return end
  smokeT = 0
  for wi, lvl in pairs(smoke) do
    local n, hub = treadNode(wi)
    if n and hub then pcall(function() obj:addParticleByNodesRelative(n, hub, -1.5, lvl > 0.6 and SMOKE_MEDIUM or SMOKE_SMALL, 0, 1) end) end
  end
end

local function frame(dt)
  if not enabled then return end
  smokeFrame(dt)
  if not tyres then build() if not tyres then return end pcall(function() extensions.load('carSurfaceFxTyreLook') end) end
  for wi, e in pairs(tyres) do powerSum[wi] = (powerSum[wi] or 0) + credit(e, dt) * dt end
  if reapply > 0 then
    reapply = reapply - 1
    if reapply == 0 then for wi, e in pairs(tyres) do e.applied = {} applyGrip(wi, e, true) end end
  end
  timer, report = timer + dt, report + dt
  if timer >= TICK then
    local events = tick(timer)
    timer = 0
    if report >= REPORT then report = 0 sendState(events) elseif events then sendState(events) end
  end
end

-- ---- interface to the game side and the other car modules
function M.setConfig(tbl)                          -- fields of csfx_tyrerules.defaults(); a table of fields to change
  if type(tbl) ~= 'table' then return end
  for k, val in pairs(tbl) do
    if k == 'enabled' then enabled = val and true or false
    elseif k == 'compounds' then              -- the Mods page's per-compound overrides over the rules' table
      for name, o in pairs(type(val) == 'table' and val or {}) do
        if R.COMPOUNDS[name] and type(o) == 'table' then for f, x in pairs(o) do if type(x) == 'number' then R.COMPOUNDS[name][f] = x end end end
      end
    elseif type(val) == 'table' and type(cfg[k]) == 'table' then for k2, v2 in pairs(val) do cfg[k][k2] = v2 end
    else cfg[k] = val end
  end
  if tyres then for wi, e in pairs(tyres) do e.applied = {} end end
  if not enabled and tyres then M.restore() end
end
-- nil: the stock class again. axle 'front' | 'rear' fits that axle only (its tyres are new: wear and temperature start over), nil fits the whole car and rebuilds every tyre.
function M.setCompound(name, axle)
  if name ~= nil and not R.COMPOUNDS[name] then return end
  if axle == 'front' or axle == 'rear' then
    fitAxle[axle] = name
    for wi, e in pairs(tyres or {}) do
      if axleOf(e.wd) == axle then
        pcall(M.putOut, wi)
        e.t = R.new(name or compound or e.stock, e.t.n, e.t.r, e.t.w, ambientC())
        e.ratio = R.swapRatio(e.stock, e.t.compound)
        e.applied = {}
      end
    end
    return
  end
  if name == compound and next(fitAxle) == nil then return end
  M.restore()
  compound, fitAxle = name, {}
  tyres = nil
end
-- a tread left as a fraction of new (1 new .. 0 at the belts), the same on every slot: a part-worn used tyre or a garage tyre change. One wheel, or all. Clears flat spots and the blown state.
function M.setTread(frac, wi)
  frac = min(1, max(0, tonumber(frac) or 1))
  for k, e in pairs(tyres or {}) do
    if wi == nil or wi == k then
      pcall(M.putOut, k)
      for j = 1, 2 * e.t.n do e.t.h[j] = frac * e.t.c.h0 end
      e.t.blown, e.t.cord, e.t.fire, e.t.hold = false, 0, nil, 0
      R.clearEnergy(e.t)
      for i = 1, e.t.n do e.t.flash[i] = 0 end
      e.applied = {}
    end
  end
end
function M.setEnv(tbl) for k, val in pairs(tbl or {}) do env[k] = val end end   -- wet 0..1, water 0..1, surface, ambient C, road C
function M.setExternal(kind, wi, m)                -- another module's multiplier on one wheel's tread grip (1 = none)
  external[kind] = external[kind] or {}
  external[kind][wi] = m ~= 1 and m or nil
  local e = tyres and tyres[wi]
  if e and enabled then applyGrip(wi, e, false) end
end
function M.setSurfaces(tbl) surfaceOf = {} for id, name in pairs(type(tbl) == 'table' and tbl or {}) do surfaceOf[tonumber(id)] = name end end
-- a tyre fire reaches the car (only with the setting on): the flammable node of the car nearest to the wheel is lit; the game's own fire system takes it from there
function M.igniteNearest(wi)
  local e, fl = tyres and tyres[wi], fire and fire.debugData and fire.debugData.flammableNodes
  if not (e and fl and fire.igniteNode and e.wd.node1 and v.data.nodes[e.wd.node1]) then return false end
  local p, best, bd = v.data.nodes[e.wd.node1].pos
  for cid in pairs(fl) do
    local n = v.data.nodes[cid]
    if n and n.pos and not e.slotOf[cid] then
      local d = (n.pos.x - p.x) ^ 2 + (n.pos.y - p.y) ^ 2 + (n.pos.z - p.z) ^ 2
      if not bd or d < bd then best, bd = cid, d end
    end
  end
  if best then fire.igniteNode(best, 600) end
  return best ~= nil
end
-- a tyre fire with the setting "Fires can spread to the car" ON: the game's own fire system is given one flammable tread node (probe f10: flames, smoke, sound; the tyre stays intact until our
-- own pop). Needs a real burn rate (0.05 gave nothing visible). The game radiates heat from a burning node to every flammable node around it (probe f10: the whole car burned), so this is only ever lit when
-- the player asked for spread, and putOut stops the node itself (the game keeps it in a hot-node list the flammable table does not reach).
local BURN_RATE, BURN_ENERGY, IGNITE_TEMP = 3, 5000, 900
function M.lightTyre(wi)
  local e, fl = tyres and tyres[wi], fire and fire.debugData and fire.debugData.flammableNodes
  if not (e and fl and fire.igniteNode) then return false end
  local cid = e.cids[1]
  fl[cid] = { name = 'csfx_tread', flashPoint = 350, smokePoint = 200, burnRate = BURN_RATE, staticBaseTemp = 20, useThermalsBaseTemp = false, conductionRadius = 0, selfIgnitionCoef = 0,
    temperature = 20, intensity = 0, chemEnergy = BURN_ENERGY, originalChemEnergy = BURN_ENERGY, weightSpecHeatCoef = 0.2, lastUnderWaterValue = 0, flameTick = 0, smokeTick = 0,
    vaporState = 0, isVapor = 0, ignoreContainerBeamBreakMessage = true, containerBeamBroken = false, canIgnite = true }
  fire.igniteNode(cid, IGNITE_TEMP)
  e.fireCid = cid
  return true
end
function M.putOut(wi)
  local e, fl = tyres and tyres[wi], fire and fire.debugData and fire.debugData.flammableNodes
  if not (e and e.fireCid and fl) then return false end
  local node = fl[e.fireCid]
  if node then node.chemEnergy, node.temperature, node.intensity = 0, 20, 0 end
  fl[e.fireCid] = nil
  e.fireCid = nil
  return true
end
function M.active() return enabled and tyres ~= nil end
function M.snapshot()                              -- wheel index -> JSON-safe state (rules snapshot)
  local out = {}
  for wi, e in pairs(tyres or {}) do out[wi] = R.snapshot(e.t) end
  return out
end
function M.restoreSnapshot(blob)                   -- keys may be strings after a json round trip
  if tyres then for wi, b in pairs(blob or {}) do local k = tonumber(wi) if tyres[k] then R.restore(tyres[k].t, b) end end else pendingBlob = blob end
end
function M.repair(wi)
  for k in pairs(tyres or {}) do if wi == nil or wi == k then pcall(M.putOut, k) end end                              -- fresh tread (a garage tyre change): one wheel, or all
  for k, e in pairs(tyres or {}) do
    if wi == nil or wi == k then e.t = R.new(fittedTo(e.wd) or e.stock, e.t.n, e.t.r, e.t.w, ambientC()) e.applied = {} end
  end
end
function M.water()                                 -- per wheel: the water depth it counts (0 none, 0.3 contact patch under water, 0.7 hub under water) and the depth in force with the environment's
  if enabled and not tyres then pcall(build) end                -- right after a compound change the tyres are rebuilt on the next frame: answer anyway
  local out = {}
  for wi, e in pairs(tyres or {}) do out[#out + 1] = string.format('%s %s own %.2f in force %.2f', tostring(wi), tostring(e.wd.name), e.water or 0, max(env.water, e.water or 0)) end
  table.sort(out)
  return table.concat(out, ' | ')
end
function M.grip()                                  -- the mean friction factor written on each tyre (1 = the car's own stock friction): a grip check that needs no driving
  if enabled and not tyres then pcall(build) end                -- right after a compound change the tyres are rebuilt on the next frame: answer anyway
  local out = {}
  for wi, e in pairs(tyres or {}) do
    local sum, n = 0, 0
    for _, f in pairs(e.applied) do sum, n = sum + f, n + 1 end
    out[#out + 1] = string.format('%s %s %s %.3f', tostring(wi), tostring(e.wd.name), e.t.compound, n > 0 and sum / n or 1)
  end
  table.sort(out)
  return table.concat(out, ' | ')
end
function M.dump()                                  -- one line per tyre: wheel index, name, hottest surface, fire, deepest wear, blown, deflated (for tests in the game)
  if enabled and not tyres then pcall(build) end                -- right after a compound change the tyres are rebuilt on the next frame: answer anyway
  local out = {}
  for wi, e in pairs(tyres or {}) do
    local minH = math.huge
    for j = 1, 2 * e.t.n do minH = min(minH, e.t.h[j]) end
    minH = max(0, minH)
    out[#out + 1] = string.format('%s %s Ts %.0f fire %s h %.2f blown %s deflated %s', tostring(wi), tostring(e.wd.name), e.t.Ts, tostring(e.t.fire), minH, tostring(e.t.blown), tostring(e.wd.isTireDeflated))
  end
  table.sort(out)
  return table.concat(out, ' | ')
end
function M.status()
  if enabled and not tyres then pcall(build) end                -- right after a compound change the tyres are rebuilt on the next frame: answer anyway
  local n, worst, hot = 0, math.huge, 0
  for _, e in pairs(tyres or {}) do
    n = n + 1
    for j = 1, 2 * e.t.n do worst = min(worst, e.t.h[j]) end
    hot = max(hot, e.t.Ts)
  end
  return string.format('enabled %s tyres %d worst tread %.2f mm hottest %.0f C compound %s', tostring(enabled), n, n > 0 and max(0, worst) or 0, hot, tostring(compound))
end

-- every tread node back to its stock friction (the module is switched off, or unloaded)
function M.restore()
  if carSurfaceFxTyreLook then pcall(carSurfaceFxTyreLook.restore) end
  for wi in pairs(tyres or {}) do pcall(M.putOut, wi) end
  for _, e in pairs(tyres or {}) do
    if not e.wd.isTireDeflated then
      for j, cid in ipairs(e.cids) do pcall(function() obj:setNodeFrictionSlidingCoefs(cid, e.base[j][1], e.base[j][2]) end) end
    end
    e.applied = {}
  end
end

function M.updateGFX(dt)                           -- our code never gets to disable the vehicle: one error switches the tyres of this car off, logged once
  if failed then return end
  local ok, err = pcall(frame, dt or 0)
  if not ok then failed = tostring(err) pcall(M.restore) log('E', 'carSurfaceFxTyres', 'switched off after an error: ' .. failed) end
end
function M.onReset()                               -- the game gives the car back with new tyres (inflated, no damage): so do we (the career restores its own saved wear after a respawn)
  reapply = REAPPLY_FRAMES
  M.repair()
  local n = 0 for _ in pairs(tyres or {}) do n = n + 1 end
  log('D', 'carSurfaceFxTyres', 'reset: ' .. n .. ' tyres renewed')
  timer, report = 0, 0
end
function M.onExtensionUnloaded() pcall(M.restore) end

return M
