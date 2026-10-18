-- Car Surface FX: the one documented call of the old body-dirt module, surfaceFXBody.wash() (a car wash or a garage service calls it). It washes the player's car through the new module.
-- Everything else the old module had (dump, paint scratches) has no equivalent here and answers nil, with one log line.
local M = { csfxShim = true }
local warned = {}

function M.wash()
  local c = rawget(_G, 'carSurfaceFx')
  if c and c.wash then return c.wash() end
end

function M.dump() if not warned.dump then warned.dump = true log('W', 'surfaceFXBody', 'surfaceFXBody.dump has no equivalent in Car Surface FX; use carSurfaceFx.status()') end end

return M
