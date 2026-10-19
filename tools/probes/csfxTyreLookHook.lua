-- DIAGNOSIS extension (not shipped): puts tyre stage materials into the car's glowMap while the car is loaded (the GE hook onJbeamLoadingPhase2), so the engine builds those switches
-- itself at spawn and runs them through its precompile (common/jbeam/materials.lua), the way it does for lights. Question: does a switch made that way render with its textures (lettered tyre)?
-- Use: copy to a scratch mod's lua/ge/extensions/, GE: extensions.load('csfxTyreLookHook'), then SPAWN (or respawn) the car; then
--   GE: local v=be:getPlayerVehicle(0) local msc=v:getSwitchableMaterial('tire_01a','tire_01a','<a tire mesh>') v:switchMaterial(msc,'csfx_tire_01a_s5')
--   (the on state of the glowMap entry) and again with 'csfx_tire_01a_s3' (the on_intense state); look at the tyre: lettered or flat black?
local M = {}
function M.onJbeamLoadingPhase2(loadingProgress, objID, vehicle)
  vehicle.glowMap = vehicle.glowMap or {}
  vehicle.glowMap.tire_01a = { off = 'tire_01a', on = 'csfx_tire_01a_s5', on_intense = 'csfx_tire_01a_s3', simpleFunction = 'csfx_never' }
  log('I', 'csfxTyreLookHook', 'glowMap tire_01a added for car ' .. tostring(objID))
end
return M
