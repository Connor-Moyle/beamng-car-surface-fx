-- DIAGNOSIS extension (not shipped). Two ways to make a runtime switch-in render with its textures (a switch made after spawn shows flat black):
--  E2 (proven): while the car's jbeam loads (GE hook onJbeamLoadingPhase2) put tyre stage materials into the car's glowMap, so the engine builds and precompiles those switches at spawn.
--  E3 (this file, the second part): at the end of the spawn (onVehicleSpawned, same frame) make the switches ourselves and run each through ALL five stage materials once, before the first frame.
-- Use: copy to a scratch mod's lua/ge/extensions/, GE: extensions.load('csfxTyreLookHook'), then SPAWN (not reset) the car. Then (GE):
--   CSFXH = extensions.csfxTyreLookHook  (or the global csfxTyreLookHook)
--   return csfxTyreLookHook.show(1, 4)     -- mesh 1 (sorted list), stage 4: s4 is NOT in the glowMap entry, so this is the E3 test; lettered/worn or flat black?
--   return csfxTyreLookHook.show(1, 5) / show(1, 3) -- the glowMap states; show(1, 0) puts the car's own material back; show(1,2), show(1,1) the others
local M = {}
local names = require('csfx_tyrelook_names')
M.msc = {}                       -- vehicle id -> { meshIndex -> msc }
local function tireMeshes(veh)
  local out = {}
  for m in tostring(veh:getMeshesContainingMaterial('tire_01a') or ''):gmatch('%S+') do out[#out + 1] = m end
  table.sort(out)
  return out
end
function M.onJbeamLoadingPhase2(loadingProgress, objID, vehicle)
  vehicle.glowMap = vehicle.glowMap or {}
  vehicle.glowMap.tire_01a = { off = 'tire_01a', on = 'csfx_tire_01a_s5', on_intense = 'csfx_tire_01a_s3', simpleFunction = 'csfx_never' }
end
function M.onVehicleSpawned(id)
  local veh = be:getObjectByID(id)
  if not veh then return end
  M.msc[id] = {}
  for k, mesh in ipairs(tireMeshes(veh)) do
    local msc = veh:getSwitchableMaterial('tire_01a', 'tire_01a', mesh)
    M.msc[id][k] = msc
    if msc and msc >= 0 then
      for st = 1, 5 do veh:switchMaterial(msc, 'csfx_tire_01a_s' .. st) end
      veh:resetMaterials(msc)
    end
  end
  log('I', 'csfxTyreLookHook', 'precompiled ' .. #M.msc[id] .. ' tyre switches for car ' .. tostring(id))
end
function M.show(k, stage)
  local veh = be:getPlayerVehicle(0)
  local msc = M.msc[veh:getId()] and M.msc[veh:getId()][k]
  if not msc then return 'no switch for mesh ' .. tostring(k) .. ' (spawn the car after loading this extension)' end
  if stage == 0 then veh:resetMaterials(msc) else veh:switchMaterial(msc, 'csfx_tire_01a_s' .. stage) end
  return 'mesh ' .. k .. ' msc ' .. tostring(msc) .. ' stage ' .. stage
end
return M
