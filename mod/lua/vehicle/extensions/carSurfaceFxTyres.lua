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
local APPLY_EPS = 0.005             -- a change under 0.5 % is not worth the call
local REAPPLY_FRAMES = 2            -- after a reset the engine restores its own friction first (our onReset runs before its resets): write again two frames later

local cfg = R.defaults()
local compound = nil                -- nil: every tyre keeps its stock class (what the car's own friction already is); a name fits that compound on all of them
local env = { wet = 0, water = 0, surface = 'asphalt', ambient = nil, road = nil }
local tyres = nil                   -- wheel index -> { t = rules tyre, wd, cids = {j -> cid}, slotOf = {cid -> j}, base = {j -> {fc, sfc}}, applied = {j -> factor}, pNom }
local external = {}                 -- kind -> { wheel index -> multiplier }
local surfaceOf = {}                 -- collision material id -> surface key of the rules (the game side sends it from the level's ground models)
local RUBBER_MAT = 4                -- the tyre's own material id; the ground is the other one
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

local function groundOf(wd)
  local id = wd.contactMaterialID1 or -1
  if id == RUBBER_MAT then id = wd.contactMaterialID2 or -1 end
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
        e.t = R.new(compound or e.stock, #tn / 2, tonumber(wd.radius), tonumber(wd.tireWidth), ambientC())
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
  local ctx = { water = e.water or env.water, v = abs(tonumber(e.wd.wheelSpeed) or 0), surface = e.surface or env.surface }
  local wet = env.wet
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
  R.addEnergy(t, j, p * dt * 0.5)
  R.addEnergy(t, mate, p * dt * 0.5)
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
      e.water = max(env.water or 0, (obj.inWater and wd.node1 and pcalls(obj.inWater, obj, wd.node1)) and 1 or 0)
      local ctx = { surface = e.surface or env.surface, wet = env.wet > 0.3, pressure = pr, pNom = e.pNom }
      R.wearStep(t, ctx, cfg)
      local dg, dT = R.takeDebris(t, cfg)
      e.debrisG = (e.debrisG or 0) + dg
      if e.debrisG >= DEBRIS_FLUSH_G then events = events or {} events[#events + 1] = { wi, 'debris', e.debrisG, dT } e.debrisG = 0 end
      R.tempStep(t, { dt = dt, power = (powerSum[wi] or 0) / dt, v = abs(tonumber(wd.wheelSpeed) or 0), fz = tonumber(wd.downForce) or 0, ambient = ambientC(),
        road = env.road, wet = env.wet, brake = tonumber(wd.brakeSurfaceTemperature), pressure = pr, pNom = e.pNom }, cfg)
      local ev = R.fireStep(t, dt, env.wet, cfg)
      if ev then events = events or {} events[#events + 1] = { wi, ev } if ev == 'spread' and cfg.fireSpread then pcall(M.igniteNearest, wi) end end
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
    parts[#parts + 1] = string.format('{%d,%d,%.1f,%.1f,%.2f,%s,%s,%.1f,%.0f}', wi, R.stage(e.t, cfg), e.t.Ts, e.t.Tc, worst, tostring(e.t.blown), tostring(e.t.fire ~= nil), M.shake(wi))
  end
  local ev = {}
  for _, x in ipairs(events or {}) do ev[#ev + 1] = x[3] and string.format('{%d,%q,%.2f,%.0f}', x[1], x[2], x[3], x[4] or 0) or string.format('{%d,%q}', x[1], x[2]) end
  obj:queueGameEngineLua(string.format('if carSurfaceFx_tyres then carSurfaceFx_tyres.state(%d,{%s},{%s}) end', obj:getId(), table.concat(parts, ','), table.concat(ev, ',')))
end

local function frame(dt)
  if not enabled then return end
  if not tyres then build() if not tyres then return end end
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
function M.setCompound(name)                       -- nil: the stock class again. Fitting rebuilds the tyres (new tyres: wear and temperature start over)
  if name ~= nil and not R.COMPOUNDS[name] then return end
  if name == compound then return end
  M.restore()
  compound = name
  tyres = nil
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
function M.active() return enabled and tyres ~= nil end
function M.snapshot()                              -- wheel index -> JSON-safe state (rules snapshot)
  local out = {}
  for wi, e in pairs(tyres or {}) do out[wi] = R.snapshot(e.t) end
  return out
end
function M.restoreSnapshot(blob)                   -- keys may be strings after a json round trip
  if tyres then for wi, b in pairs(blob or {}) do local k = tonumber(wi) if tyres[k] then R.restore(tyres[k].t, b) end end else pendingBlob = blob end
end
function M.repair(wi)                              -- fresh tread (a garage tyre change): one wheel, or all
  for k, e in pairs(tyres or {}) do
    if wi == nil or wi == k then e.t = R.new(compound or e.stock, e.t.n, e.t.r, e.t.w, ambientC()) e.applied = {} end
  end
end
function M.status()
  local n, worst, hot = 0, math.huge, 0
  for _, e in pairs(tyres or {}) do
    n = n + 1
    for j = 1, 2 * e.t.n do worst = min(worst, e.t.h[j]) end
    hot = max(hot, e.t.Ts)
  end
  return string.format('enabled %s tyres %d worst tread %.2f mm hottest %.0f C compound %s', tostring(enabled), n, n > 0 and worst or 0, hot, compound)
end

-- every tread node back to its stock friction (the module is switched off, or unloaded)
function M.restore()
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
function M.onReset() reapply = REAPPLY_FRAMES if tyres then for _, e in pairs(tyres) do e.applied = {} end end timer, report = 0, 0 end
function M.onExtensionUnloaded() pcall(M.restore) end

return M
