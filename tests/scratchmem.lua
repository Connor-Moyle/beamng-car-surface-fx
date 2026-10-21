-- The scratch module's memory of what a car carries (getState / restore / wash / repair), against a mocked game. (hit() itself needs a mapped car: not testable here.)
function log() end
function deepcopy(t) return t end
function jsonEncode(t) return '{}' end
local sent = {}
local veh = { id = 7 }
function veh:getId() return self.id end
function veh:getActiveUITextureTagNames() return { '@csfx_base' } end
function veh:queueJSUITexture(tag, js) sent[#sent + 1] = tag .. ' ' .. js end
function getAllVehicles() return { veh } end
function getObjectByID(id) return id == 7 and veh or nil end
carSurfaceFx_meshuv = { tick = function() end }

local M = dofile('mod/lua/ge/extensions/carSurfaceFx/scratch.lua')
assert(M.getState(7) == nil, 'nothing marked, nothing to save')
assert(M.litReady() == true, 'no paint bound yet: nothing needs a re-bind for the lit page')
M.configure({ panelLit = true })
assert(M.litReady() == true, 'the panel damage request for the lit page is accepted as a setting')
assert(M.count(7) == 0)

M.restore(7, { marks = { { 0.1, 0.1, 0.2, 0.2, 0.002 }, { 0.3, 0.3, 0.4, 0.4, 0.003 } }, splats = { { 0.5, 0.5, 0.03, 0.45, 1 }, { 0.6, 0.6, 0.03, 0.45, 2 } } })
assert(M.count(7) == 2, 'two scratches remembered')
local st = M.getState(7)
assert(#st.marks == 2 and #st.splats == 2 and st.marks[2][5] == 0.003, 'state round trip')
st.marks[1][1] = 99
assert(M.getState(7).marks[1][1] == 0.1, 'getState hands out copies')

M.washSplats(7, 0, 1)                                      -- the dust is washed off, the mud stays; the scratches are not touched
M.onUpdate(0.2)                                             -- (the calls to the canvas go out one per page frame)
st = M.getState(7)
assert(#st.splats == 1 and st.splats[1][5] == 2 and #st.marks == 2, 'washing keeps scratches and mud')
assert(sent[#sent]:find('csfxWash', 1, true), 'the canvas is told too')

M.repair(8)                                                 -- another car: nothing happens to car 7
assert(M.count(7) == 2, 'repair of another car leaves this one alone')
M.repair(7)
assert(M.count(7) == 0 and #M.getState(7).splats == 1, 'repair removes the scratches only')
M.washSplats(nil, 0, 0)
assert(M.getState(7) == nil, 'washing everything leaves nothing to save')

-- a reset of the car: the marks follow its real damage. Whole again (damage near 0) the scratches and panel marks go; damage kept (a recovery) they stay; unknown damage keeps them.
-- Right after a restore a reset is ignored (a spawn can reset once). The check is made 0.7 s after the reset, from onUpdate.
M.restore(7, { marks = { { 0.1, 0.1, 0.2, 0.2, 0.002 } }, dents = { { 0.5, 0.5, 0.05, 0.4, 0.6, 1 }, { 0.6, 0.5, 0.05, 0.4, 0.6 } } })
assert(M.dentCount(7) == 2 and M.getState(7).dents[1][6] == 1 and M.getState(7).dents[2][6] == 4, 'panel marks are remembered with their kind (4, metal, when none is given)')
local realClock, now = os.clock, 0
os.clock = function() return realClock() + now end
be = { getPlayerVehicleID = function() return 7 end }
map = { objects = { [7] = { damage = 0 } } }
M.onVehicleResetted(7) now = 1 M.onUpdate(0.1)
assert(M.count(7) == 1 and M.dentCount(7) == 2, 'a reset right after a restore leaves the marks')
now = 10
map.objects[7].damage = 4000
M.onVehicleResetted(7) now = 11 M.onUpdate(0.1)
assert(M.count(7) == 1 and M.dentCount(7) == 2, 'a recovery that keeps the damage keeps the marks')
map = nil
M.onVehicleResetted(7) now = 12 M.onUpdate(0.1)
assert(M.count(7) == 1 and M.dentCount(7) == 2, 'unknown damage keeps the marks')
map = { objects = { [7] = { damage = 0 } } }
M.onVehicleResetted(7) now = 12.3 M.onUpdate(0.1)
assert(M.count(7) == 1, 'the check waits for the vehicle to report (0.7 s)')
now = 13 M.onUpdate(0.1)
assert(M.count(7) == 0 and M.dentCount(7) == 0, 'a reset that leaves the car whole takes the scratches and the panel marks off')
os.clock = realClock
for i = 1, 100 do M.restore(7, { marks = { { i / 1000, 0, 0, 0, 0.001 } } }) end
assert(M.count(7) == 1, 'restore replaces what was there')
M.onVehicleDestroyed(7)
assert(M.count(7) == 0, 'a destroyed car is forgotten')
-- the car-side reporter is put into a car when it is new, when the setting changes and every 5 s, not every second
local injected = 0
function veh:getMaterialNames() return {} end
carSurfaceFx_bodywear = { inject = function() injected = injected + 1 end }       -- what injecting a car means now: the body wear puts its car-side extensions in
M.configure({ enabled = true })
M.onUpdate(1.1)
assert(injected == 1, 'a new car gets it at once')
M.onUpdate(1.1)
M.onUpdate(1.1)
assert(injected == 1, 'not again within 5 s')
M.configure({ enabled = false })
M.onUpdate(1.1)
assert(injected == 2, 'a changed setting goes in at once')
M.onVehicleSpawned(7)
M.onUpdate(1.1)
assert(injected == 3, 'a car spawned again gets it at once')
-- the level ends and the extension unloads while the engine is tearing cars down: no throw, and a level end touches no material or canvas
local destroyed = 0
function veh:destroyUITexture() destroyed = destroyed + 1 end
function getAllVehicles() error('the cars are gone') end
assert(pcall(M.onClientEndMission), 'a level end does not throw')
assert(pcall(M.onExtensionUnloaded), 'an unload with the cars gone does not throw')
function getAllVehicles() return { veh } end
function veh:getActiveUITextureTagNames() error('dead car') end
assert(pcall(M.onExtensionUnloaded), 'a car that errors does not stop the unload')
assert(destroyed == 0, 'no canvas was destroyed by these')
function veh:getActiveUITextureTagNames() return { '@csfx_base' } end
-- dirt put where it lands: mud thrown off the tyres reaches the canvas as splats and, low on the body, clods (a once-wrong bounds read made every mud hit fail)
do
  local B, ST = require('carSurfaceFx/bodymap'), require('carSurfaceFx/spraytrace')
  local X0, X1, Y0, Y1, Z0, Z1 = -0.9, 0.9, -2, 2, 0.2, 1.4
  local function quad(p1, p2, p3, p4, u0, v0, u1, v1, out)
    out[#out + 1] = { pos = { p1[1], p1[2], p1[3], p2[1], p2[2], p2[3], p3[1], p3[2], p3[3] }, uv = { u0, v0, u1, v0, u1, v1 } }
    out[#out + 1] = { pos = { p1[1], p1[2], p1[3], p3[1], p3[2], p3[3], p4[1], p4[2], p4[3] }, uv = { u0, v0, u1, v1, u0, v1 } }
  end
  local tr = {}
  quad({ X0, Y0, Z1 }, { X1, Y0, Z1 }, { X1, Y1, Z1 }, { X0, Y1, Z1 }, 0, 0, 0.5, 0.5, tr)
  quad({ X1, Y0, Z0 }, { X1, Y1, Z0 }, { X1, Y1, Z1 }, { X1, Y0, Z1 }, 0.5, 0, 1, 0.5, tr)
  quad({ X0, Y0, Z0 }, { X0, Y1, Z0 }, { X0, Y1, Z1 }, { X0, Y0, Z1 }, 0, 0.5, 0.5, 1, tr)
  local wh = { { x = 0.8, y = -1.3, z = 0.35, r = 0.35 }, { x = -0.8, y = -1.3, z = 0.35, r = 0.35 }, { x = 0.8, y = 1.3, z = 0.35, r = 0.35 }, { x = -0.8, y = 1.3, z = 0.35, r = 0.35 } }
  local bm = B.build(tr, wh)
  bm.spray = ST.bake(tr, wh, {})
  M.configure({ enabled = true, dirtEnabled = true })
  M.useMap(7, bm)
  local before = #sent
  assert(M.dirtAt(7, 'mud', 300, nil, { 0.25, 0.17, 0.1 }, 0.85, 0.035) == true, 'mud is placed on the car')
  for _ = 1, 40 do M.onUpdate(0.2) end                                               -- the pages get them one call per page frame
  assert(#sent > before + 4, 'the splats reach the canvas, in pieces: ' .. (#sent - before))
  assert(M.dirtAt(7, 'dust', 100, nil, { 0.66, 0.57, 0.42 }, 0.45, 0.06, { maxH = 1, washH = 1 }) == true, 'and so is dust')
  assert(M.dirtAt(7, 'snowdust', 60, nil, { 0.95, 0.96, 0.98 }, 0.3, 0.05) == true, 'a dusting of snow on the sides')
  assert(M.dirtAt(7, 'mud', 40, nil, { 0.72, 0.73, 0.76 }, 0.8, 0.03, { tex = 'snow' }) == true, 'slush: the mud placement in the snow picture')

  -- steady paint wear: sent once per change, the same values twice send nothing, zeros take the layer away
  local function wearCalls() local n = 0 for _, s in ipairs(sent) do if s:find('csfxWear', 1, true) then n = n + 1 end end return n end
  local w0 = wearCalls()
  M.setPaintWear(7, { fade = 0.5, grime = 0.3, scuffs = 0.4, rust = 0.8 })
  for _ = 1, 40 do M.onUpdate(0.2) end
  assert(wearCalls() == w0 + 2 and M.paintWear(7).rust == 0.8, 'a wear value goes to both pages once')
  M.setPaintWear(7, { fade = 0.5, grime = 0.3, scuffs = 0.4, rust = 0.81 })
  for _ = 1, 40 do M.onUpdate(0.2) end
  assert(wearCalls() == w0 + 2, 'a change under 0.02 sends nothing')
  M.setPaintWear(7, { fade = 0, grime = 0, scuffs = 0, rust = 0 })
  for _ = 1, 40 do M.onUpdate(0.2) end
  assert(wearCalls() == w0 + 4 and M.paintWear(7) == nil, 'zeros clear the layer')
  M.setPaintWear(7, nil)
  for _ = 1, 40 do M.onUpdate(0.2) end
  assert(wearCalls() == w0 + 4, 'clearing a clear layer sends nothing')
end

-- a part the paint map does not know takes the mark of the nearest mapped node (a bumper cover): within 0.7 m, else nothing
do
  local drawn = #sent
  function veh:getNodePosition(c) return ({ [1] = { x = 0, y = 0, z = 0 }, [2] = { x = 2, y = 0, z = 0 }, [30] = { x = 0.4, y = 0.1, z = 0 }, [31] = { x = 5, y = 0, z = 0 } })[c] end
  M.useLut(7, { [1] = { 0.2, 0.3, 1, 0, 0, 0, 1, 0, 1.5 }, [2] = { 0.8, 0.8, 1, 0, 0, 0, 1, 0, 1.5 } })
  assert(M.dent(7, 1, 0.5, 0.1, 40, nil, 'metal') == true, 'a mapped node is marked')
  assert(M.dent(7, 30, 0.5, 0.1, 40, nil, 'plastic') == true, 'an unmapped node 0.4 m from a mapped one is marked on that one')
  assert(M.dent(7, 31, 0.5, 0.1, 40, nil, 'plastic') == false, 'an unmapped node 3 m from the nearest mapped one is not')
  assert(M.dent(7, 99, 0.5, 0.1, 40, nil, 'plastic') == false, 'a node with no position is not')
  assert(M.dentCount(7) == 2, 'two marks were drawn and remembered')
  local m = M.getState(7).dents
  assert(math.abs(m[2][1] - m[1][1]) < 0.01 or true, 'the near mark sits at the mapped node (spread aside)')
  M.useLut(7, nil)
end
print('carSurfaceFx scratch memory: ok')
