-- Car Surface FX: where the frame time goes. A benchmark, not part of the mod (nothing loads it): while you drive in heavy rain it switches the effects on one after the
-- other (from everything off), measures the frame time of each step, and also the time the Lua of the mod itself takes, so the rest (the web pages' canvases, the texture
-- uploads, the material reloads, the GPU) is the difference.
--   extensions.load('carSurfaceFx_bench')
--   carSurfaceFx.debug('rain', 1)               -- (or real heavy rain) so the wet paint and the glass are on in every step
--   carSurfaceFx_bench.run()                    -- about 100 s: 8 steps of 5 s to settle and 7 s to measure; drive in the driver camera at a steady speed meanwhile
--   carSurfaceFx_bench.report()                 -- the table (also in beamng.log and settings/csfx_bench.txt when it ends)
-- The settings are put back as they were when it ends (or carSurfaceFx_bench.stop()).
local M = {}

local SETTLE, MEASURE = 5, 7
local clock = (os and os.clockhp) or os.clock

-- the steps, each cumulative on the one before: { name, { group, key, value }... }
M.STEPS = {
  { 'everything off', { 'windscreen', 'enabled', false }, { 'windscreen', 'overlay', false }, { 'scratch', 'enabled', false }, { 'scratch', 'water', false }, { 'scratch', 'dirtEnabled', false },
    { 'mud', 'enabled', false }, { 'weather', 'snow', false }, { 'weather', 'frost', false }, { 'weather', 'bugs', false }, { 'weather', 'spray', false } },
  { '+ paint canvases (marks and scratches)', { 'scratch', 'enabled', true } },
  { '+ rain drops on the paint', { 'scratch', 'water', true } },
  { '+ window canvases', { 'windscreen', 'enabled', true } },
  { '+ cockpit overlay', { 'windscreen', 'overlay', true } },
  { '+ dirt and mud', { 'mud', 'enabled', true }, { 'scratch', 'dirtEnabled', true } },
  { '+ frost and snow', { 'weather', 'snow', true }, { 'weather', 'frost', true } },
  { '+ bugs and road spray', { 'weather', 'bugs', true }, { 'weather', 'spray', true } },
}

local state                  -- nil when idle
local results = {}
local luaTime = {}           -- 'ext.hook' -> accumulated seconds in the current measurement
local wrapped = {}

local function wrapLua()
  for _, name in ipairs({ 'carSurfaceFx', 'carSurfaceFx_scratch', 'carSurfaceFx_meshuv', 'carSurfaceFx_grass', 'carSurfaceFx_marks', 'carSurfaceFx_fluids' }) do
    local mod = rawget(_G, name)
    if type(mod) == 'table' then
      for _, hook in ipairs({ 'onUpdate', 'onPreRender' }) do
        local original = mod[hook]
        if type(original) == 'function' then
          local key = name .. '.' .. hook
          mod[hook] = function(...)
            local t0 = clock()
            original(...)
            luaTime[key] = (luaTime[key] or 0) + (clock() - t0)
          end
          wrapped[#wrapped + 1] = { mod = mod, hook = hook, original = original }
        end
      end
    end
  end
end

local function unwrapLua()
  for i = #wrapped, 1, -1 do local w = wrapped[i] w.mod[w.hook] = w.original end
  wrapped = {}
end

local function setting(group, key, value)
  local fx = rawget(_G, 'carSurfaceFx')
  if not (fx and fx.setSetting) then return nil, 'carSurfaceFx is not loaded' end
  return fx.setSetting(group, key, value)
end

local function applyStep(step)
  for i = 2, #step do
    local old = setting(step[i][1], step[i][2], step[i][3])
    local id = step[i][1] .. '.' .. step[i][2]
    if state.saved[id] == nil and old ~= nil then state.saved[id] = { step[i][1], step[i][2], old } end
  end
end

local function restore()
  for _, s in pairs(state and state.saved or {}) do setting(s[1], s[2], s[3]) end
end

local function percentile(list, p)
  if #list == 0 then return 0 end
  table.sort(list)
  return list[math.max(1, math.min(#list, math.ceil(#list * p)))]
end

local function finishStep()
  local frames, sum = #state.dts, 0
  for _, d in ipairs(state.dts) do sum = sum + d end
  local lua = 0
  for _, t in pairs(luaTime) do lua = lua + t end
  local detail = {}
  for k, t in pairs(luaTime) do if t > 0 then detail[#detail + 1] = string.format('%s %.3f', k, t * 1000 / math.max(1, frames)) end end
  table.sort(detail)
  results[#results + 1] = { name = M.STEPS[state.i][1], frames = frames, ms = frames > 0 and sum * 1000 / frames or 0, p95 = percentile(state.dts, 0.95) * 1000, lua = lua * 1000 / math.max(1, frames), detail = table.concat(detail, ', ') }
end

function M.report()
  local lines = { string.format('%-42s %8s %8s %8s %8s %6s', 'step (cumulative)', 'ms/frame', 'p95 ms', 'vs first', 'lua ms', 'frames') }
  local base = results[1] and results[1].ms or 0
  for _, r in ipairs(results) do
    lines[#lines + 1] = string.format('%-42s %8.2f %8.2f %+8.2f %8.3f %6d   %s', r.name, r.ms, r.p95, r.ms - base, r.lua, r.frames, r.detail)
  end
  if #results > 1 then
    local last = results[#results]
    lines[#lines + 1] = string.format('all on against all off: %+.2f ms per frame, of which the mod\'s own Lua is %.3f ms (the rest is the pages, the texture uploads, the material reloads and the GPU)', last.ms - base, last.lua - results[1].lua)
  end
  for _, l in ipairs(lines) do log('I', 'carSurfaceFx_bench', l) end
  if writeFile then pcall(writeFile, '/settings/csfx_bench.txt', table.concat(lines, '\n') .. '\n') end
  return table.concat(lines, '\n')
end

function M.run()
  if state then return 'already running' end
  if not rawget(_G, 'carSurfaceFx') then return 'carSurfaceFx is not loaded' end
  results, luaTime = {}, {}
  state = { i = 0, saved = {}, t = 0, phase = 'settle', dts = {} }
  wrapLua()
  return string.format('benchmark started: %d steps of %d s + %d s; drive steadily in the driver camera', #M.STEPS, SETTLE, MEASURE)
end

local function nextStep()
  state.i = state.i + 1
  if state.i > #M.STEPS then
    unwrapLua()
    restore()
    state = nil
    M.report()
    return
  end
  applyStep(M.STEPS[state.i])
  state.t, state.phase, state.dts = 0, 'settle', {}
  luaTime = {}
end

function M.onUpdate(dtReal)
  if not state then return end
  if state.i == 0 then nextStep() return end
  state.t = state.t + dtReal
  if state.phase == 'settle' then
    if state.t >= SETTLE then state.t, state.phase, state.dts, luaTime = 0, 'measure', {}, {} end
  else
    state.dts[#state.dts + 1] = dtReal
    if state.t >= MEASURE then
      finishStep()
      nextStep()
    end
  end
end

function M.stop()
  if not state then return 'not running' end
  unwrapLua()
  restore()
  state = nil
  return 'stopped, settings put back'
end

function M.onExtensionUnloaded() pcall(M.stop) end

function M.status()
  if not state then return 'idle, ' .. #results .. ' steps measured' end
  return string.format('step %d of %d (%s), %s, %.1f s', state.i, #M.STEPS, M.STEPS[state.i] and M.STEPS[state.i][1] or '-', state.phase, state.t)
end

return M
