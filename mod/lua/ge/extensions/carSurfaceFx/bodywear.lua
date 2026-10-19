-- Car Surface FX: body wear, game side. The car side (vehicle/extensions/carSurfaceFxWear.lua) sorts every contact and sends the hits; this module turns hits into marks
-- (scratches and scuffs through the paint canvases of carSurfaceFx/scratch.lua; gouges in the ground through carSurfaceFx_ruts) and keeps the counts of everything the car saw, so carSurfaceFx.status() and the QA run can say why a
-- scrape left nothing: no contact at all, contacts too light, not sliding, only tyres, or a hit that was drawn.
--   carSurfaceFx_bodywear.hit(id, node, kind, mat, force, slip, speed, a, b, c)   a hit: kind 'ground' | 'wall' | 'vehicle' | 'unknown'; a, b, c = its sliding direction along the car's left / back / up lines
--   carSurfaceFx_bodywear.report(id, seen, hits, light, still, tyre, wheel, cool, maxForce, maxSlip)   the counts of the last second
--   carSurfaceFx_bodywear.status()   one line; carSurfaceFx_bodywear.debug(true) logs every hit
local M = {}

local TAG = 'carSurfaceFx_bodywear'
local totals = { seen = 0, hits = 0, light = 0, still = 0, tyre = 0, wheel = 0, cool = 0, maxForce = 0, maxSlip = 0, ground = 0, wall = 0, vehicle = 0, unknown = 0, drawn = 0 }
local last = {}                  -- the last few hits, newest last
local LAST_N = 12
local debugOn = false
local injectT = 0

function M.hit(id, node, kind, mat, force, slip, speed, a, b, c)
  totals.hits = totals.hits + 1
  totals[kind] = (totals[kind] or 0) + 1
  last[#last + 1] = string.format('%s n%d F%.0f s%.1f m%d', kind, node, force, slip, mat)
  if #last > LAST_N then table.remove(last, 1) end
  if debugOn then log('I', TAG, string.format('hit car %d node %d %s force %.0f slip %.1f speed %.1f mat %d dir %.2f %.2f %.2f', id, node, kind, force, slip, speed, mat, a, b, c)) end
  if kind == 'ground' then
    local ruts = rawget(_G, 'carSurfaceFx_ruts')                  -- a panel on the ground gouges it (the ruts module draws it, when its gouges switch is on)
    if ruts and ruts.gouge then ruts.gouge(id, node, mat, force) totals.drawn = totals.drawn + 1 end
  end
  local scratch = rawget(_G, 'carSurfaceFx_scratch')
  if scratch and kind ~= 'ground' then                          -- a body panel against a wall or another car leaves scratches; the ground is for gouges (to come)
    scratch.hit(id, node, force, slip, a, b, c)
    totals.drawn = totals.drawn + 1
  end
end

function M.report(id, seen, hits, light, still, tyre, wheel, cool, maxForce, maxSlip)
  totals.seen, totals.light, totals.still, totals.tyre, totals.wheel, totals.cool = totals.seen + seen, totals.light + light, totals.still + still, totals.tyre + tyre, totals.wheel + wheel, totals.cool + cool
  if maxForce > totals.maxForce then totals.maxForce = maxForce end
  if maxSlip > totals.maxSlip then totals.maxSlip = maxSlip end
end

function M.status()
  return string.format('contacts seen %d: hits %d (ground %d, wall %d, vehicle %d, unknown %d; drawn %d), rejected: tyre %d, wheel %d, light %d, not sliding %d, too soon %d; strongest force %.0f N, fastest slip %.1f m/s; last [%s]',
    totals.seen, totals.hits, totals.ground, totals.wall, totals.vehicle, totals.unknown, totals.drawn, totals.tyre, totals.wheel, totals.light, totals.still, totals.cool, totals.maxForce, totals.maxSlip, table.concat(last, ', '))
end

function M.totals() return totals end
function M.clear() for k in pairs(totals) do totals[k] = 0 end last = {} end
function M.debug(on) debugOn = on and true or false return 'body wear debug ' .. tostring(debugOn) end
function M.debugOn() return debugOn end

-- every few seconds: the cars that wear get the car-side extensions (the player's; the others when carSurfaceFx.scratch.allVehicles is set)
function M.inject(veh, on)
  veh:queueLuaCommand(string.format('if not carSurfaceFxContact then extensions.load("carSurfaceFxContact") end if not carSurfaceFxWear then extensions.load("carSurfaceFxWear") end carSurfaceFxWear.setConfig(%s, %s)', on and 'true' or 'false', debugOn and 'true' or 'false'))
end

function M.onExtensionUnloaded()
  for _, v in ipairs(getAllVehicles()) do v:queueLuaCommand('if carSurfaceFxWear then carSurfaceFxWear.setConfig(false, false) end') end
end

require('carSurfaceFx/guard').wrap(M, TAG, { 'hit', 'report' })
return M
