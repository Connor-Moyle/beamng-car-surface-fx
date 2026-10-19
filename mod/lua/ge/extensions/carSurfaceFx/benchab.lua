-- Car Surface FX: a quiet A/B benchmark, one feature at a time. The cumulative bench (bench.lua) cannot tell a feature's cost from the noise of heavy rain and traffic; this one parks
-- the car, switches ONE feature off and on in alternation (off, on, off, on, off, on), measures each window, and reports the median of each side, so a few ms of drift cancel out.
--   extensions.load('carSurfaceFx_benchab')
--   (parked car, no traffic, rain frozen or forced with carSurfaceFx.debug('rain', 1), a fixed camera; everything else as the test needs it)
--   carSurfaceFx_benchab.run('leaks')    -- about 150 s; carSurfaceFx_benchab.features() lists the names; carSurfaceFx_benchab.report() when it ends
-- The settings are put back when it ends (or carSurfaceFx_benchab.stop()).
local M = {}

local SETTLE, MEASURE, REPS = 4, 20, 3
M.FEATURES = {
  leaks = { { 'fluids', 'enabled' } },
  glass = { { 'windscreen', 'enabled' }, { 'windscreen', 'windows' } },
  overlay = { { 'windscreen', 'overlay' } },
  dirt = { { 'mud', 'enabled' }, { 'scratch', 'dirtEnabled' } },
  marks = { { 'marks', 'enabled' } },
  paintwater = { { 'scratch', 'water' } },
  paint = { { 'scratch', 'enabled' } },
  weather = { { 'weather', 'snow' }, { 'weather', 'frost' }, { 'weather', 'bugs' }, { 'weather', 'spray' } },
}

local state
local results = {}           -- feature -> { off = { { ms, p99 }... }, on = ... }

local function setting(group, key, value)
  local fx = rawget(_G, 'carSurfaceFx')
  if not (fx and fx.setSetting) then return nil end
  return fx.setSetting(group, key, value)
end

local function sorted(list)
  local c = {}
  for i, v in ipairs(list) do c[i] = v end
  table.sort(c)
  return c
end
local function median(list)
  if #list == 0 then return 0 end
  return sorted(list)[math.ceil(#list / 2)]
end
local function percentile(list, p)
  if #list == 0 then return 0 end
  local c = sorted(list)
  return c[math.max(1, math.min(#c, math.ceil(#c * p)))]
end

-- windows: off, on, off, on, off, on
local function apply(on)
  for _, s in ipairs(M.FEATURES[state.feature]) do
    local old = setting(s[1], s[2], on)
    if state.saved[s[1] .. '.' .. s[2]] == nil and old ~= nil then state.saved[s[1] .. '.' .. s[2]] = { s[1], s[2], old } end
  end
end

local function restore()
  for _, s in pairs(state and state.saved or {}) do setting(s[1], s[2], s[3]) end
end

function M.features() local n = {} for k in pairs(M.FEATURES) do n[#n + 1] = k end table.sort(n) return table.concat(n, ', ') end

function M.run(feature)
  if state then return 'already running' end
  if not M.FEATURES[feature or ''] then return 'unknown feature, use one of: ' .. M.features() end
  if not rawget(_G, 'carSurfaceFx') then return 'carSurfaceFx is not loaded' end
  results[feature] = { off = {}, on = {} }
  state = { feature = feature, saved = {}, i = 0, t = 0, phase = 'settle', dts = {} }
  return string.format('A/B bench of %s: %d windows of %d s + %d s, about %d s; keep the car and the camera still', feature, REPS * 2, SETTLE, MEASURE, REPS * 2 * (SETTLE + MEASURE))
end

local function nextWindow()
  state.i = state.i + 1
  if state.i > REPS * 2 then
    restore()
    state = nil
    return
  end
  apply(state.i % 2 == 0)                                       -- window 1 off, 2 on, 3 off ...
  state.t, state.phase, state.dts = 0, 'settle', {}
end

function M.onUpdate(dtReal)
  if not state then return end
  if state.i == 0 then nextWindow() return end
  state.t = state.t + dtReal
  if state.phase == 'settle' then
    if state.t >= SETTLE then state.t, state.phase, state.dts = 0, 'measure', {} end
  else
    state.dts[#state.dts + 1] = dtReal
    if state.t >= MEASURE then
      local sum = 0
      for _, d in ipairs(state.dts) do sum = sum + d end
      local side = state.i % 2 == 0 and 'on' or 'off'
      local r = results[state.feature][side]
      r[#r + 1] = { ms = sum * 1000 / math.max(1, #state.dts), p99 = percentile(state.dts, 0.99) * 1000 }
      nextWindow()
    end
  end
end

local function column(list, key) local c = {} for i, r in ipairs(list) do c[i] = r[key] end return c end

function M.report()
  local lines = { string.format('%-12s %10s %10s %10s %10s %10s %10s', 'feature', 'off ms', 'on ms', 'delta ms', 'off p99', 'on p99', 'delta p99') }
  local names = {}
  for k in pairs(results) do names[#names + 1] = k end
  table.sort(names)
  for _, k in ipairs(names) do
    local r = results[k]
    local a, b, c, d = median(column(r.off, 'ms')), median(column(r.on, 'ms')), median(column(r.off, 'p99')), median(column(r.on, 'p99'))
    lines[#lines + 1] = string.format('%-12s %10.2f %10.2f %+10.2f %10.2f %10.2f %+10.2f   (%d off and %d on windows)', k, a, b, b - a, c, d, d - c, #r.off, #r.on)
    local spread = {}
    for i, w in ipairs(r.off) do spread[#spread + 1] = string.format('off%d %.2f', i, w.ms) end
    for i, w in ipairs(r.on) do spread[#spread + 1] = string.format('on%d %.2f', i, w.ms) end
    lines[#lines + 1] = '             windows: ' .. table.concat(spread, ', ')
  end
  for _, l in ipairs(lines) do if log then log('I', 'carSurfaceFx_benchab', l) end end
  if writeFile then pcall(writeFile, '/settings/csfx_benchab.txt', table.concat(lines, '\n') .. '\n') end
  return table.concat(lines, '\n')
end

function M.stop()
  if not state then return 'not running' end
  restore()
  state = nil
  return 'stopped, settings put back'
end

function M.onExtensionUnloaded() pcall(M.stop) end
function M.status() if not state then return 'idle' end return string.format('window %d of %d (%s), %s, %.1f s', state.i, REPS * 2, state.feature, state.phase, state.t) end

return M
