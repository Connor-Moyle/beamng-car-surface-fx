-- The game side of the tyres (carSurfaceFx/tyres.lua) with stub engine calls: loading the car module, the state coming back, the hook, the career API.
local sent, hooks = {}, {}
local veh = { queueLuaCommand = function(_, c) sent[#sent + 1] = c end }
be = { getObjectByID = function(_, id) return id == 7 and veh or nil end, getPlayerVehicleID = function() return 7 end }
extensions = { hook = function(name, ...) hooks[#hooks + 1] = { name, ... } end }
function jsonEncode(t) return 'J' end
function jsonDecode(s) return { [0] = { compound = 'road' } } end
local T = dofile('mod/lua/ge/extensions/carSurfaceFx/tyres.lua')

T.update(0.1, 0.4)
assert(#sent == 0, 'off: nothing is sent to any car')
T.configure({ enabled = true, wearRate = 5, blowout = { enabled = true } })
assert(T.getConfig().wearRate == 5 and T.getConfig().blowout.enabled and T.getConfig().blowout.maxForce == 3000, 'settings merge, nested too')
T.update(0.1, 0.4)
assert(#sent == 1 and sent[1]:find('extensions.load("carSurfaceFxTyres")', 1, true) and sent[1]:find('setConfig', 1, true), 'the player car gets the module and the settings')
T.update(1.0, 0.4)
assert(sent[#sent]:find('setEnv({wet=0.40})', 1, true), 'the weather reaches the car once a second')

T.state(7, { { 0, 1, 80, 40, 0.1, false, false }, { 1, 2, 90, 45, 0, false, false } }, {})
local g = T.getTyres(7)
assert(#g.wheels == 2 and g.wheels[1].idx == 0 and g.wheels[1].stage == 1 and g.wheels[2].Ts == 90, 'getTyres lists the wheels in order')
assert(T.getTyres(99) == nil, 'an unknown car: nil')
assert(#hooks == 0, 'nothing blown, no hook')
T.state(7, { { 0, 5, 80, 40, 0.1, true, false } }, { { 0, 'pop' } })
local blown, ev = 0, 0
for _, h in ipairs(hooks) do if h[1] == 'onCsfxTyreBlown' and h[2] == 7 and h[3] == 0 then blown = blown + 1 end if h[1] == 'onCsfxTyreEvent' and h[4] == 'pop' then ev = ev + 1 end end
assert(blown == 1 and ev == 1, 'a blow-out raises the hook once, and the event')
T.state(7, { { 0, 5, 80, 40, 0.1, true, false } }, {})
blown = 0 for _, h in ipairs(hooks) do if h[1] == 'onCsfxTyreBlown' then blown = blown + 1 end end
assert(blown == 1, 'and not again on the next report')

assert(T.setCompound(7, nil, 'slick') and sent[#sent]:find('setCompound("slick")', 1, true), 'a compound is sent to the car')
assert(not T.setCompound(7, nil, 'unobtainium'), 'an unknown compound is refused')
assert(T.setTread(7, nil, 1) and sent[#sent]:find('repair()', 1, true), 'new tread repairs all')
assert(T.setTread(7, 1, 1) and sent[#sent]:find('repair(1)', 1, true), 'or one wheel')
assert(not T.setTread(7, 1, 0.5), 'partial tread is not supported yet')
assert(T.snapshot(7) == nil, 'no snapshot before the car sends one')
T.gotSnapshot(7, 'x')
assert(T.snapshot(7)[0].compound == 'road', 'a snapshot from the car is kept')
local n = #sent
assert(T.restore(7, { [0] = {} }) and #sent == n + 1 and sent[#sent]:find('restoreSnapshot', 1, true), 'restore goes to the car')
assert(not T.restore(7, 'x'), 'a bad blob is refused')
T.forget(7)
assert(T.getTyres(7) == nil, 'forgotten when the car is destroyed')
print('carSurfaceFx tyres (game side): ok')
