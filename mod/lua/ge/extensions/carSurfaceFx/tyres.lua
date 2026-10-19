-- Car Surface FX: tyre wear, temperature and grip, game side (rules: lua/common/csfx_tyrerules.lua; the car side: lua/vehicle/extensions/carSurfaceFxTyres.lua).
-- This module loads the car module into the cars it watches, feeds it the settings and the weather, keeps the last state each car reported (2 Hz), and is the API for the career
-- (Street Legal): getTyres, setCompound, setTread, snapshot / restore, and the hook onCsfxTyreBlown(vehId, wheelIdx). Debris, smoke and fire visuals are driven from the events here.
local M = {}
local R = require('csfx_tyrerules')

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

local function load_(id)
  send(id, 'if not carSurfaceFxTyres then extensions.load("carSurfaceFxTyres") end carSurfaceFxTyres.setConfig(jsonDecode(' .. lit(cfg) .. '))')
end

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

function M.attach(id)
  if watched[id] then return end
  watched[id] = true
  load_(id)
end
function M.forget(id) watched[id], states[id], snaps[id] = nil, nil, nil end
M.onVehicleDestroyed = M.forget
function M.onVehicleSpawned(id) if watched[id] then load_(id) end end          -- a respawn: new car VM, give it the module again (state comes back with restore)

-- called by carSurfaceFx every frame: the weather to the cars once a second, a snapshot of each car every 5 s (for the career save)
function M.update(dt, wet)
  lastWet = wet or lastWet
  if cfg.enabled then local pid = be and be:getPlayerVehicleID(0) if pid and pid >= 0 then M.attach(pid) end end
  envT, snapT = envT + dt, snapT + dt
  if envT >= 1 then
    envT = 0
    for id in pairs(watched) do send(id, string.format('if carSurfaceFxTyres then carSurfaceFxTyres.setEnv({wet=%.2f}) end', lastWet)) end
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
    s[w[1]] = { stage = w[2], Ts = w[3], Tc = w[4], worstFlat = w[5], blown = w[6], onFire = w[7] }
    if w[6] and not wasBlown and extensions and extensions.hook then extensions.hook('onCsfxTyreBlown', id, w[1]) end
  end
  for _, e in ipairs(events or {}) do
    if extensions and extensions.hook then extensions.hook('onCsfxTyreEvent', id, e[1], e[2]) end
  end
end
function M.gotSnapshot(id, json) local ok, t = pcall(jsonDecode, json) if ok and type(t) == 'table' then snaps[id] = t end end

-- ---- the career API
-- { wheels = { { idx, stage, Ts, Tc, flat, blown, onFire } ... } } or nil when the car is not tracked yet
function M.getTyres(id)
  local s = states[id]
  if not s then return nil end
  local out = { compound = nil, wheels = {} }
  for wi, w in pairs(s) do out.wheels[#out.wheels + 1] = { idx = wi, stage = w.stage, Ts = w.Ts, Tc = w.Tc, flat = w.worstFlat, blown = w.blown, onFire = w.onFire } end
  table.sort(out.wheels, function(a, b) return a.idx < b.idx end)
  return out
end
-- a compound for the whole car (the car module does not split axles yet: axle is ignored); the car's tyres are rebuilt as a new set
function M.setCompound(id, axle, name)
  if not R.COMPOUNDS[name] then return false end
  send(id, string.format('if carSurfaceFxTyres then carSurfaceFxTyres.setCompound(%q) carSurfaceFxTyres.repair() end', name))
  return true
end
-- fresh tread: frac 1 = new on every wheel (or the wheel index). Partial wear is not supported by the car module yet.
function M.setTread(id, wheelIdx, frac)
  if (frac or 1) < 1 then return false end
  send(id, wheelIdx and string.format('if carSurfaceFxTyres then carSurfaceFxTyres.repair(%d) end', wheelIdx) or 'if carSurfaceFxTyres then carSurfaceFxTyres.repair() end')
  return true
end
function M.snapshot(id) return snaps[id] end                    -- up to 5 s old; nil when the car has not sent one
function M.restore(id, blob)
  if type(blob) ~= 'table' then return false end
  snaps[id] = blob
  send(id, 'if carSurfaceFxTyres then carSurfaceFxTyres.restoreSnapshot(jsonDecode(' .. lit(blob) .. ')) end')
  return true
end

return M
