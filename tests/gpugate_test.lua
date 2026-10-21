-- The GPU gate (carSurfaceFx/gpugate.lua): planes hold after a material reload, and Street Legal's gate is used when it loads.
local G = require('carSurfaceFx/gpugate')
G.reset()
assert(G.planesMayChange(0), 'nothing reloaded: planes may change')
G.reloaded(10)
assert(not G.planesMayChange(10.5), 'half a second after a reload the planes wait')
assert(G.planesMayChange(10 + G.WET_HOLD), 'and go on after the hold')
G.planesTouched(12)
assert(G.lastPlanes() == 12, 'a plane change is noted')
G.forget()
assert(G.shared() == G, 'without Street Legal the gate is this one')
local sl = { planesMayChange = function() return false end, reloaded = function() end, planesTouched = function() end }
package.loaded['sl/core/gpugate'] = sl
G.forget()
assert(G.shared() == sl, 'with Street Legal loaded its gate is shared')
package.loaded['sl/core/gpugate'] = nil
G.forget()
G.reset()
print('carSurfaceFx gpugate: ok')
