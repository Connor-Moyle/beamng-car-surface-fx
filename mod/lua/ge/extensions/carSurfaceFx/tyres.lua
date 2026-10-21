-- Car Surface FX: tyre wear, temperature and grip, game side (rules: lua/common/csfx_tyrerules.lua; the car side: lua/vehicle/extensions/carSurfaceFxTyres.lua).
-- This module loads the car module into the cars it watches, feeds it the settings and the weather, keeps the last state each car reported (2 Hz), and is the API for the career
-- (Street Legal): getTyres, setCompound, setTread, snapshot / restore, and the hook onCsfxTyreBlown(vehId, wheelIdx). Debris, smoke and fire visuals are driven from the events here.
local M = {}
local R = require('csfx_tyrerules')
local marbles = require('carSurfaceFx/marbles')

local cfg = R.defaults()
cfg.enabled = false                        -- off until the settings switch it on
local watched = {}                              -- vehicle id -> true (cars that carry the car module)
local states = {}                               -- vehicle id -> { [wi] = { stage, Ts, Tc, worstFlat, blown, onFire } }
local snaps = {}                                -- vehicle id -> the last snapshot the car sent (wheel index -> blob)
local envT, snapT = 0, 0
local lastWet = 0

local function vehOf(id) return be and be:getObjectByID(id) end
local function lit(s) return '[==[' .. jsonEncode(s) .. ']==]' end            -- a json string as a Lua long string for queueLuaCommand
local function send(id, code) local v = vehOf(id) if v then v:queueLuaCommand(code) end end

-- collision-type id -> surface key of the rules, for the level's ground models (the car looks up the ground under each wheel with it)
local function surfaceTable()
  local t = {}
  for name, gm in pairs(core_environment and core_environment.groundModels or {}) do
    local key = R.surfaceOfGround(name)
    local id = gm.cdata and gm.cdata.collisiontype
    if key and id then t[id] = key end
  end
  return t
end

local function load_(id)
  send(id, 'if not carSurfaceFxTyres then extensions.load("carSurfaceFxTyres") end carSurfaceFxTyres.setConfig(jsonDecode(' .. lit(cfg) .. ')) carSurfaceFxTyres.setSurfaces(jsonDecode(' .. lit(surfaceTable()) .. '))')
end

-- the visuals are drawn by emitters that carSurfaceFx's visuals (ba) set: flame(vehId, wheelIdx, on), smoke(vehId, wheelIdx, level 0..1), pop(vehId, wheelIdx), debris(vehId, wheelIdx, grams, tempC), bang(vehId, wheelIdx), panel(vehId, wheelIdx, strength)
-- (panel = the crack or scuff decal on the arch and bumper beside a blown tyre, ba's panel damage; visual only, no force is applied to the car).
-- Without them the events are dropped; an error in one never reaches the car.
-- the default visuals: the car module throws the game's own smoke and rubber chunks; fire is the game's (lightTyre). carSurfaceFx may replace any of these through setEmitters
local function fx(kind) return function(id, wi, a) send(id, string.format('if carSurfaceFxTyres then carSurfaceFxTyres.fx("%s", %d, %s) end', kind, wi, tostring(tonumber(a) or 0))) end end
local emitters = { smoke = fx('smoke'), pop = fx('pop'), debris = fx('debris') }
function M.setEmitters(t) emitters = type(t) == 'table' and t or {} end
local function emit(name, ...) local f = emitters[name] if f then pcall(f, ...) end end


-- the settings (fields of csfx_tyrerules.defaults(), `enabled` switches the simulation on); pushed to every watched car
function M.configure(t)
  if type(t) == 'table' then
    for k, v in pairs(t) do
      if type(v) == 'table' and type(cfg[k]) == 'table' then for k2, v2 in pairs(v) do cfg[k][k2] = v2 end else cfg[k] = v end
    end
  end
  for id in pairs(watched) do load_(id) end
  return cfg
end
-- the Mods page's file (carSurfaceFx/tyresSchema.lua): its layout is the cfg's, plus compounds.<name>.<field> overrides; a missing key keeps its default
function M.reload()
  local f = jsonReadFile and jsonReadFile(require('carSurfaceFx/tyresSchema').FILE)
  if type(f) ~= 'table' then return cfg end
  f.preset = nil
  return M.configure(f)
end
function M.getConfig() return cfg end
function M.clearMarbles() marbles.clear() for id in pairs(watched) do send(id, 'if carSurfaceFxTyres then carSurfaceFxTyres.setMarbles({}) end') end end
M.onClientEndMission = function() marbles.clear() end
-- the patches are drawn as decals, through the marks module's one engine call when it is loaded
function M.onPreRender(dt)
  if not (cfg.marbles.enabled and marbles.count() > 0) then return end
  if not (Engine and Engine.Render and Engine.Render.DynamicDecalMgr) then return end
  local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
  local mk = rawget(_G, 'carSurfaceFx_marks')
  marbles.draw(cfg, cam and cam.x, cam and cam.y, function(pl, n) if mk and mk.drawBatch then mk.drawBatch(pl, n) else Engine.Render.DynamicDecalMgr.addDecals(pl, n) end end)
end

function M.lookEvent(id, wi, what, n)                  -- one-off facts from the car's look and spark code, written here because the car's own log does not reach beamng.log
  log('I', 'carSurfaceFx_tyres', string.format('car %s wheel %s: %s (%s)', tostring(id), tostring(wi), tostring(what), tostring(n)))
end
local lookMsc = {}                                -- vehicle id -> { 'material|mesh' -> switch id } (see M.look)
function M.attach(id)
  if watched[id] then return end
  watched[id] = true
  load_(id)
end
function M.forget(id) watched[id], states[id], snaps[id], lookMsc[id] = nil, nil, nil, nil end
M.onVehicleDestroyed = M.forget
function M.onVehicleSpawned(id) lookMsc[id] = nil if watched[id] then load_(id) end end          -- a respawn: new car VM, give it the module again (state comes back with restore)

-- The wear look. The engine only accepts a material switch to a target that was made part of the car at spawn (a runtime switch-in renders flat black), so while a car's jbeam loads (the hook below)
-- the stage materials are put into its glowMap: on = csfx_<tyre>_worn, on_intense = csfx_<tyre>_belts; the engine then builds and precompiles those switches itself. Only cars spawned after the tyres are
-- switched on have them (a car in the level needs a respawn). The car module sends up a wheel's stage and its tyre meshes as { {original material, mesh}, ... }; the switch is made here, one per mesh.
-- Rules stage 0..2: the car's own tyre; 3 and 4 (under half the tread): worn; 5 (the belts): the cords.
local LOOK_NAMES = require('csfx_tyrelook_names')
function M.onJbeamLoadingPhase2(loadingProgress, objID, vehicle)
  if not cfg.enabled or type(vehicle) ~= 'table' then return end
  vehicle.glowMap = vehicle.glowMap or {}
  for _, name in ipairs(LOOK_NAMES) do
    if not vehicle.glowMap[name] then vehicle.glowMap[name] = { off = name, on = 'csfx_' .. name .. '_worn', on_intense = 'csfx_' .. name .. '_belts', simpleFunction = 'csfx_never' } end
  end
  log('I', 'carSurfaceFx_tyres', 'wear look: glowMap entries added for car ' .. tostring(objID))
end
function M.look(id, wi, stage, list)
  local v = vehOf(id)
  if not v then return end
  lookMsc[id] = lookMsc[id] or {}
  for _, p in ipairs(list or {}) do
    local key = p[1] .. '|' .. p[2]
    local msc = lookMsc[id][key]
    if not msc then msc = v:getSwitchableMaterial(p[1], p[1], p[2]) lookMsc[id][key] = msc end
    if msc and msc >= 0 then
      if stage < 3 then v:resetMaterials(msc) else v:switchMaterial(msc, 'csfx_' .. p[1] .. (stage >= 5 and '_belts' or '_worn')) end
    end
  end
end
-- called by carSurfaceFx every frame: the weather to the cars once a second, a snapshot of each car every 5 s (for the career save)
local RAIN_FILM, filmSent = 0.2, false
local marbleT = 0
function M.update(dt, wet)
  lastWet = wet or lastWet
  if cfg.marbles.enabled or marbles.count() > 0 then
    local burning = marbles.step(cfg, dt, 20, lastWet)
    marbleT = marbleT + dt
    local packed = marbles.pack(marbleT >= 2)          -- when something changed, and every 2 s anyway (a respawned car)
    if packed then
      marbleT = 0
      for id in pairs(watched) do send(id, 'if carSurfaceFxTyres then carSurfaceFxTyres.setMarbles(' .. packed .. ') end') end
    end
  end
  if cfg.enabled then local pid = be and be:getPlayerVehicleID(0) if pid and pid >= 0 then M.attach(pid) end end
  envT, snapT = envT + dt, snapT + dt
  if envT >= 1 then
    envT = 0
    -- heavy rain leaves a film of water on the road: depth 0 below wetness 0.8, up to RAIN_FILM at 1 (rainAquaplane); a toggled-off option clears it once
    local film = cfg.rainAquaplane and RAIN_FILM * math.max(0, (lastWet - 0.8) / 0.2) or 0
    local extra = (film > 0 or filmSent) and string.format(',water=%.2f', film) or ''
    filmSent = film > 0
    for id in pairs(watched) do send(id, string.format('if carSurfaceFxTyres then carSurfaceFxTyres.setEnv({wet=%.2f%s}) end', lastWet, extra)) end
  end
  if snapT >= 5 then
    snapT = 0
    for id in pairs(watched) do
      send(id, string.format('if carSurfaceFxTyres then obj:queueGameEngineLua(string.format("if carSurfaceFx_tyres then carSurfaceFx_tyres.gotSnapshot(%%d, [==[%%s]==]) end", obj:getId(), jsonEncode(carSurfaceFxTyres.snapshot()))) end'))
    end
  end
end

-- from the car, 2 Hz and at once on an event: list of { wi, stage, Ts, Tc, worstFlat, blown, onFire } and a list of { wi, 'ignite'|'pop'|'out'|'spread' }
function M.state(id, ws, events)
  local s = states[id] or {}
  states[id] = s
  for _, w in ipairs(ws or {}) do
    local wasBlown = s[w[1]] and s[w[1]].blown
    local wasSmoking = s[w[1]] and s[w[1]].smoking
    s[w[1]] = { stage = w[2], Ts = w[3], Tc = w[4], worstFlat = w[5], blown = w[6], onFire = w[7], shakeHz = w[8], shakeN = w[9], tread = w[10], h0 = w[11], compound = w[12], name = w[13] }
    if w[6] and not wasBlown and extensions and extensions.hook then extensions.hook('onCsfxTyreBlown', id, w[1]) end
    local sm = not w[6] and R.smoke(w[3] or 0, cfg) or 0      -- (the Tyre smoke switch is in R.smoke; the fires switch is not its business)
    if sm > 0 or wasSmoking then emit('smoke', id, w[1], sm) end
    s[w[1]].smoking = sm > 0
  end
  for _, e in ipairs(events or {}) do
    if extensions and extensions.hook then extensions.hook('onCsfxTyreEvent', id, e[1], e[2]) end
    if e[2] == 'ignite' then emit('flame', id, e[1], true)
    elseif e[2] == 'out' or e[2] == 'pop' then emit('flame', id, e[1], false) if e[2] == 'pop' then emit('pop', id, e[1]) emit('bang', id, e[1]) if cfg.blowout.enabled then emit('panel', id, e[1], cfg.blowout.strength) end end
    elseif e[2] == 'debris' then
      emit('debris', id, e[1], e[3], e[4])
      if e[5] then marbles.add(cfg, e[3], e[4], e[5], e[6], e[7]) end          -- (the contact patch's world position, when the wheel was on the road)
    elseif e[2] == 'scuff' then marbles.scuff(e[3], (e[4] or 0) / 100) end
  end
end
function M.gotSnapshot(id, json) local ok, t = pcall(jsonDecode, json) if ok and type(t) == 'table' then snaps[id] = t end end

-- ---- the career API
-- { wheels = { { idx, stage, Ts, Tc, flat, blown, onFire } ... } } or nil when the car is not tracked yet
function M.getTyres(id)
  local s = states[id]
  if not s then return nil end
  local out = { compound = nil, wheels = {} }
  for wi, w in pairs(s) do
    local nm = tostring(w.name or ''):upper()                  -- FL FR RL RR: the car's own wheel names
    local ax = nm:sub(1, 1) == 'F' and 'front' or (nm:sub(1, 1) == 'R' and 'rear' or nil)
    local sd = nm:sub(-1) == 'L' and 'left' or (nm:sub(-1) == 'R' and 'right' or nil)
    local frac = w.tread and w.h0 and w.h0 > 0 and R.clamp(w.tread / w.h0, 0, 1) or nil       -- 1 new .. 0 at the belts
    out.compound = out.compound or w.compound
    out.wheels[#out.wheels + 1] = { idx = wi, stage = w.stage, Ts = w.Ts, Tc = w.Tc, flat = w.worstFlat, blown = w.blown, onFire = w.onFire, tread = w.tread, h0 = w.h0, frac = frac,
      compound = w.compound, axle = ax, side = sd, shakeHz = w.shakeHz, shakeN = w.shakeN }
  end
  table.sort(out.wheels, function(a, b) return a.idx < b.idx end)
  return out
end
-- a compound for 'front', 'rear' or (nil) the whole car; those tyres are a new set
function M.setCompound(id, axle, name)
  if not R.COMPOUNDS[name] then return false end
  if axle ~= nil and axle ~= 'front' and axle ~= 'rear' then return false end
  send(id, string.format('if carSurfaceFxTyres then carSurfaceFxTyres.setCompound(%q, %s) end', name, axle and string.format('%q', axle) or 'nil'))
  return true
end
-- the tread of a wheel (or all) set to a fraction of new, 0..1 (1 = new; a used tyre sold part-worn): clears flat spots and the blown state
function M.setTread(id, wheelIdx, frac)
  frac = tonumber(frac)
  if not frac or frac < 0 or frac > 1 then return false end
  send(id, string.format('if carSurfaceFxTyres then carSurfaceFxTyres.setTread(%.3f, %s) end', frac, wheelIdx and string.format('%d', wheelIdx) or 'nil'))
  return true
end
function M.snapshot(id) return snaps[id] end                    -- up to 5 s old; nil when the car has not sent one
function M.restore(id, blob)
  if type(blob) ~= 'table' then return false end
  snaps[id] = blob
  send(id, 'if carSurfaceFxTyres then carSurfaceFxTyres.restoreSnapshot(jsonDecode(' .. lit(blob) .. ')) end')
  return true
end

-- onPreRender runs every frame: one error switches it off (logged once) instead of repeating for every player; update() is called by carSurfaceFx.update under its own safety net
require('carSurfaceFx/guard').wrap(M, 'carSurfaceFx_tyres', { 'onPreRender' })

return M
