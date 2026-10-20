-- Game-side diagnosis of the tyre wear look (run_lua, GE; load the whole file, it returns the table D). A car is parked; D.list() first, then D.try(k, 'name') one mesh at a time with a screenshot after each.
-- Question it answers: which switch target actually changes a tyre mesh on the screen (a stock material, a loaded csfx stage, a garish loaded material), and what the engine says about each.
local D = {}
D.log = {}
local function say(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end D.log[#D.log + 1] = table.concat(t, ' ') end
local function veh() return be:getPlayerVehicle(0) end
local function meshes()
  local out = {}
  for m in tostring(veh():getMeshesContainingMaterial('tire_01a') or ''):gmatch('%S+') do out[#out + 1] = m end
  table.sort(out)
  return out
end
D.msc = {}
local function mscOf(k)
  local m = meshes()[k]
  if not m then return nil, 'no mesh ' .. k end
  if not D.msc[k] then D.msc[k] = veh():getSwitchableMaterial('tire_01a', 'tire_01a', m) end
  return D.msc[k], m
end
local function out() local s = table.concat(D.log, '\n') D.log = {} return s end

function D.list()
  say('vehicle', veh():getJBeamFilename(), 'id', veh():getId())
  for k, m in ipairs(meshes()) do say('mesh', k, m) end
  for _, n in ipairs({ 'tire_01a', 'tire_01a_old', 'csfx_tire_01a_worn', 'csfx_tire_01a_belts' }) do
    local o = scenetree.findObject(n)
    say(n, o and 'exists' or 'MISSING', o and ('class ' .. tostring(o:getClassName()) .. ' mapTo ' .. tostring(o:getField('mapTo', 0)) .. ' baseColorMap ' .. tostring(o:getField('baseColorMap', 0)) .. ' detail ' .. tostring(o:getField('detailNormalMap', 0))) or '')
  end
  for _, n in ipairs(veh():getMaterialNames() or {}) do if n:find('main') or n:find('paint') then say('car material', n) end end
  return out()
end
-- the mesh k (1-based, sorted: the order list() prints) goes to the material `name`; the call's return values are printed
function D.try(k, name)
  local msc, m = mscOf(k)
  if not msc then return m end
  say('mesh', m, 'msc', msc, 'to', name, 'material object', tostring(scenetree.findObject(name) ~= nil))
  local ok, a, b = pcall(function() return veh():switchMaterial(msc, name) end)
  say('switchMaterial ->', ok, a, b)
  return out()
end
function D.reset(k)
  local msc, m = mscOf(k)
  if not msc then return m end
  pcall(function() veh():resetMaterials(msc) end)
  return 'reset ' .. m
end
-- an edit of a loaded material in place (the way the fluids and paints work) followed by the reload
function D.reload(name)
  local o = scenetree.findObject(name)
  if not o then return 'missing ' .. name end
  local ok, e = pcall(function() Sim.upcast(o):reload() end)
  return 'reload ' .. name .. ' ' .. tostring(ok) .. ' ' .. tostring(e)
end
function D.load()
  return 'loadJsonMaterialsFile -> ' .. tostring(loadJsonMaterialsFile('/vehicles/common/carSurfaceFx/stages.materials.json'))
end
function D.commands() return 'list() | load() | try(k, material) | reset(k) | reload(material)' end
return D
