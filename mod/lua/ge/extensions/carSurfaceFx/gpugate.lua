-- Car Surface FX: a small gate so the leak puddle planes (ProceduralMesh creation and deletion) and the mod's material reloads (shader compiles) do not hit the GPU in the same
-- moments. Street Legal lost its D3D12 device when its rain reloads and puddle planes ran together, so when Street Legal is there its gate (sl/core/gpugate, the same API) is
-- used by both mods through shared(); without it this one runs. Pure: the caller passes the clock. Tested by tests/gpugate_test.lua.
local M = {}

M.WET_HOLD = 1          -- s the planes are left alone after a material reload

local lastReload, lastPlanes = -1e9, -1e9

function M.reset() lastReload, lastPlanes = -1e9, -1e9 end
function M.reloaded(now) lastReload = now end
function M.planesTouched(now) lastPlanes = now end
function M.planesMayChange(now) return now - lastReload >= M.WET_HOLD end
function M.lastPlanes() return lastPlanes end

-- Street Legal's gate when that mod is loaded (looked up once), else this one
local shared
function M.shared()
  if shared == nil then
    local ok, g = pcall(require, 'sl/core/gpugate')
    shared = ok and type(g) == 'table' and g.planesMayChange and g.reloaded and g or M
  end
  return shared
end
function M.forget() shared = nil end      -- (tests)

return M
