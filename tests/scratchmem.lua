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
assert(M.count(7) == 0)

M.restore(7, { marks = { { 0.1, 0.1, 0.2, 0.2, 0.002 }, { 0.3, 0.3, 0.4, 0.4, 0.003 } }, splats = { { 0.5, 0.5, 0.03, 0.45, 1 }, { 0.6, 0.6, 0.03, 0.45, 2 } } })
assert(M.count(7) == 2, 'two scratches remembered')
local st = M.getState(7)
assert(#st.marks == 2 and #st.splats == 2 and st.marks[2][5] == 0.003, 'state round trip')
st.marks[1][1] = 99
assert(M.getState(7).marks[1][1] == 0.1, 'getState hands out copies')

M.washSplats(7, 0, 1)                                      -- the dust is washed off, the mud stays; the scratches are not touched
st = M.getState(7)
assert(#st.splats == 1 and st.splats[1][5] == 2 and #st.marks == 2, 'washing keeps scratches and mud')
assert(sent[#sent]:find('csfxWash', 1, true), 'the canvas is told too')

M.repair(8)                                                 -- another car: nothing happens to car 7
assert(M.count(7) == 2, 'repair of another car leaves this one alone')
M.repair(7)
assert(M.count(7) == 0 and #M.getState(7).splats == 1, 'repair removes the scratches only')
M.washSplats(nil, 0, 0)
assert(M.getState(7) == nil, 'washing everything leaves nothing to save')

for i = 1, 100 do M.restore(7, { marks = { { i / 1000, 0, 0, 0, 0.001 } } }) end
assert(M.count(7) == 1, 'restore replaces what was there')
M.onVehicleDestroyed(7)
assert(M.count(7) == 0, 'a destroyed car is forgotten')
print('carSurfaceFx scratch memory: ok')
