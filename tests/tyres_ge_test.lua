-- The game side of the tyres (carSurfaceFx/tyres.lua) with stub engine calls: loading the car module, the state coming back, the hook, the career API.
log = function() end
local sent, hooks = {}, {}
local veh = { queueLuaCommand = function(_, c) sent[#sent + 1] = c end }
be = { getObjectByID = function(_, id) return id == 7 and veh or nil end, getPlayerVehicleID = function() return 7 end }
extensions = { hook = function(name, ...) hooks[#hooks + 1] = { name, ... } end }
function jsonEncode(t) local o = {} for k, v in pairs(t) do o[#o + 1] = tostring(k) .. '=' .. tostring(v) end table.sort(o) return 'J' .. table.concat(o, ',') end
function jsonDecode(s) return { [0] = { compound = 'road' } } end
core_environment = { groundModels = { ASPHALT = { cdata = { collisiontype = 3 } }, DIRT_DUSTY = { cdata = { collisiontype = 9 } }, METAL = { cdata = { collisiontype = 5 } } } }
local T = dofile('mod/lua/ge/extensions/carSurfaceFx/tyres.lua')

T.update(0.1, 0.4)
assert(#sent == 0, 'off: nothing is sent to any car')
T.configure({ enabled = true, wearRate = 5, blowout = { enabled = true } })
assert(T.getConfig().wearRate == 5 and T.getConfig().blowout.enabled and T.getConfig().blowout.maxForce == 3000, 'settings merge, nested too')
T.update(0.1, 0.4)
assert(#sent == 1 and sent[1]:find('extensions.load("carSurfaceFxTyres")', 1, true) and sent[1]:find('setConfig', 1, true), 'the player car gets the module and the settings')
assert(sent[1]:find('setSurfaces', 1, true) and sent[1]:find('3=asphalt', 1, true) and sent[1]:find('9=dirt', 1, true) and not sent[1]:find('5=', 1, true), 'the ground models become a surface table, unknown ones left out')
T.update(1.0, 0.4)
assert(sent[#sent]:find('setEnv({wet=0.40})', 1, true), 'the weather reaches the car once a second')
T.update(1.0, 1.0)
assert(not sent[#sent]:find('water', 1, true), 'rain film off by default: no water sent')
T.configure({ enabled = true, rainAquaplane = true })
T.update(1.0, 1.0)
assert(sent[#sent]:find('water=0.20', 1, true), 'full rain: a film of 0.2')
T.update(1.0, 0.9)
assert(sent[#sent]:find('water=0.10', 1, true), 'half way: 0.1')
T.update(1.0, 0.5)
assert((sent[#sent] .. sent[#sent - 1]):find('water=0.00', 1, true), 'below 0.8 the film is cleared')
T.update(1.0, 0.5)
assert(not sent[#sent]:find('water', 1, true), 'and not repeated')

T.state(7, { { 0, 1, 80, 40, 0.1, false, false, 0, 0, 6.0, 8.0, 'road', 'FL' }, { 1, 2, 90, 45, 0, false, false } }, {})
local g = T.getTyres(7)
assert(#g.wheels == 2 and g.wheels[1].idx == 0 and g.wheels[1].stage == 1 and g.wheels[2].Ts == 90, 'getTyres lists the wheels in order')
assert(math.abs(g.wheels[1].frac - 0.75) < 1e-9 and g.wheels[1].tread == 6 and g.wheels[1].axle == 'front' and g.wheels[1].side == 'left' and g.compound == 'road', 'tread fraction, axle, side and compound for the career')
assert(g.wheels[2].frac == nil and g.wheels[2].axle == nil, 'a wheel the car has not described yet has no fraction')
assert(T.getTyres(99) == nil, 'an unknown car: nil')
assert(#hooks == 0, 'nothing blown, no hook')
T.state(7, { { 0, 5, 80, 40, 0.1, true, false } }, { { 0, 'pop' } })
local blown, ev = 0, 0
for _, h in ipairs(hooks) do if h[1] == 'onCsfxTyreBlown' and h[2] == 7 and h[3] == 0 then blown = blown + 1 end if h[1] == 'onCsfxTyreEvent' and h[4] == 'pop' then ev = ev + 1 end end
assert(blown == 1 and ev == 1, 'a blow-out raises the hook once, and the event')
T.state(7, { { 0, 5, 80, 40, 0.1, true, false } }, {})
blown = 0 for _, h in ipairs(hooks) do if h[1] == 'onCsfxTyreBlown' then blown = blown + 1 end end
assert(blown == 1, 'and not again on the next report')

assert(T.setCompound(7, nil, 'slick') and sent[#sent]:find('setCompound("slick", nil)', 1, true), 'a compound is sent to the car')
assert(not T.setCompound(7, nil, 'unobtainium'), 'an unknown compound is refused')
assert(T.setCompound(7, 'rear', 'fullwet') and sent[#sent]:find('setCompound("fullwet", "rear")', 1, true), 'a compound for one axle')
assert(not T.setCompound(7, 'left', 'slick'), 'an unknown axle is refused')
assert(T.setTread(7, nil, 1) and sent[#sent]:find('setTread(1.000, nil)', 1, true), 'new tread on all')
assert(T.setTread(7, 1, 0.5) and sent[#sent]:find('setTread(0.500, 1)', 1, true), 'a part-worn tyre on one wheel')
assert(not T.setTread(7, 1, 1.5) and not T.setTread(7, 1, nil), 'a fraction outside 0..1 is refused')
assert(T.snapshot(7) == nil, 'no snapshot before the car sends one')
T.gotSnapshot(7, 'x')
assert(T.snapshot(7)[0].compound == 'road', 'a snapshot from the car is kept')
local n = #sent
assert(T.restore(7, { [0] = {} }) and #sent == n + 1 and sent[#sent]:find('restoreSnapshot', 1, true), 'restore goes to the car')
assert(not T.restore(7, 'x'), 'a bad blob is refused')
-- the visuals: the events and the smoke level reach the emitters
local log = {}
T.setEmitters({ flame = function(id, wi, on) log[#log + 1] = 'flame' .. wi .. tostring(on) end, smoke = function(id, wi, l) log[#log + 1] = string.format('smoke%d:%.2f', wi, l) end,
  pop = function(id, wi) log[#log + 1] = 'pop' .. wi end, bang = function(id, wi) log[#log + 1] = 'bang' .. wi end, panel = function(id, wi, st) log[#log + 1] = 'panel' .. wi .. ':' .. st end, debris = function(id, wi, g, t) log[#log + 1] = string.format('debris%d:%.1f:%.0f', wi, g, t) end })
T.state(7, { { 1, 2, 135, 45, 0, false, false } }, { { 1, 'ignite' }, { 1, 'debris', 2.5, 180 } })
assert(table.concat(log, ' ') == 'smoke1:0.50 flame1true debris1:2.5:180', 'smoke at 200 C is half, the ignite and the debris arrive: ' .. table.concat(log, ' '))
log = {}
T.state(7, { { 1, 2, 60, 45, 0, false, false } }, { { 1, 'pop' } })
assert(table.concat(log, ' ') == 'smoke1:0.00 flame1false pop1 bang1 panel1:1.0', 'the smoke is told once when it stops, a pop puts the flame out and bangs, and (setting on) marks the panel: ' .. table.concat(log, ' '))
T.setEmitters({ flame = function() error('boom') end })
T.state(7, { { 1, 2, 60, 45, 0, false, false } }, { { 1, 'ignite' } })        -- an emitter that fails changes nothing
T.setEmitters({})
T.forget(7)
assert(T.getTyres(7) == nil, 'forgotten when the car is destroyed')
-- the wear look: stage materials go into the glowMap of a car that loads while the tyres are on; one switch per mesh, made here and kept; rules stages 0-2 give the material back, 3-4 worn, 5 belts
local sw, calls = 0, {}
veh.getSwitchableMaterial = function(_, o, _, m) sw = sw + 1 return 40 + sw end
veh.switchMaterial = function(_, msc, m) calls[#calls + 1] = msc .. '=' .. m end
veh.resetMaterials = function(_, msc) calls[#calls + 1] = msc .. '=reset' end
T.look(7, 0, 3, { { 'tire_01a', 'tire_01a_x' } })
T.look(7, 0, 5, { { 'tire_01a', 'tire_01a_x' } })
T.look(7, 0, 1, { { 'tire_01a', 'tire_01a_x' } })
assert(sw == 1 and table.concat(calls, ' ') == '41=csfx_tire_01a_worn 41=csfx_tire_01a_belts 41=reset', 'one switch per mesh: ' .. table.concat(calls, ' '))
T.lookEvent(7, 0, 'metal', 32)
local car = {}
T.onJbeamLoadingPhase2(nil, 7, car)
assert(car.glowMap.tire_01a.on == 'csfx_tire_01a_worn' and car.glowMap.tire_01a.on_intense == 'csfx_tire_01a_belts' and car.glowMap.tire_01a.simpleFunction == 'csfx_never' and car.glowMap.tire, 'the stage materials are put into the glowMap of a car that loads while the tyres are on')
local own = { glowMap = { tire_01a = { off = 'x' } } }
T.onJbeamLoadingPhase2(nil, 7, own)
assert(own.glowMap.tire_01a.off == 'x', 'a car with its own glowMap entry for the tyre keeps it')
T.configure({ enabled = false })
local off = {}
T.onJbeamLoadingPhase2(nil, 8, off)
assert(off.glowMap == nil, 'tyres off: the car is not touched')
print('carSurfaceFx tyres (game side): ok')
