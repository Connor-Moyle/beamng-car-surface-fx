-- Car Surface FX, vehicle side of the console debug tools (P16): while on, five times a second it reports each wheel's contact (where, which game material, which ground kind, load, slip)
-- to carSurfaceFx_debug.wheels. Off by default; carSurfaceFx_debug.contacts(true) / surfaces(true) switch it on.
local M = {}
local on, timer = false, 0
local custom = {}                                  -- a map's own collision type id -> kind (setMaterials, the same list the other car extensions get)
local names

local KINDS = { 'snow', 'mud', 'sand', 'gravel', 'dirt', 'grass', 'ice', 'water', 'asphalt', 'concrete', 'rock', 'metal' }
local function kindOf(nm)
  nm = tostring(nm):lower()
  for _, k in ipairs(KINDS) do if nm:find(k, 1, true) then return k end end
  return '?'
end

local function report()
  if not wheels or not wheels.wheels then return end
  if not names then
    names = {}
    pcall(function() for id, m in pairs(particles.getMaterialsParticlesTable()) do names[id] = m and m.name end end)
  end
  local parts = {}
  for wi, wd in pairs(wheels.wheels) do
    local p1 = obj:getAbsNodePosition(wd.node1)
    local x, y, z = p1.x, p1.y, p1.z
    if wd.node2 then local p2 = obj:getAbsNodePosition(wd.node2) x, y, z = (x + p2.x) / 2, (y + p2.y) / 2, (z + p2.z) / 2 end
    local mat = wd.contactMaterialID1 or 0
    if mat == 4 then mat = wd.contactMaterialID2 or 0 end                  -- the tyre's own material is rubber (4); the ground is the other one
    local nm = names[mat] or ('id' .. tostring(mat))
    parts[#parts + 1] = string.format('{%d,%.2f,%.2f,%.2f,%q,%q,%.0f,%.2f}', wi, x, y, z - (wd.radius or 0.34), nm, custom[mat] or kindOf(nm), wd.downForce or 0, math.abs(wd.lastSlip or 0))
  end
  obj:queueGameEngineLua('if carSurfaceFx_debug then carSurfaceFx_debug.wheels(' .. obj:getId() .. ',{' .. table.concat(parts, ',') .. '}) end')
end

function M.setOn(v) on = v and true or false end
function M.setMaterials(t) custom = type(t) == 'table' and t or {} end
function M.updateGFX(dt)
  if not on then return end
  timer = timer + (dt or 0)
  if timer < 0.2 then return end
  timer = 0
  pcall(report)                                                -- our code never gets to disable the vehicle
end

return M
