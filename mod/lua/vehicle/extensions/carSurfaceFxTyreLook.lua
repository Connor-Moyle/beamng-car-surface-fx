-- Car Surface FX, vehicle side: how worn each tyre of this car looks. The tyre module reports a stage per wheel (0 new .. 4 bald, 5 belts); here each wheel's own tyre mesh is switched to the
-- file-defined material csfx_<original>_s<stage> (art/surfacefx/tyres/stages.materials.json, made by tools/make_tyre_stage_materials.py) with the engine's per-mesh switch, the way the glowMap on/off
-- materials switch. At the belts the tread nodes become METAL, so the engine's own spark and scrape rules (particles.json, METAL on asphalt) apply.
local NAMES = require('csfx_tyrelook_names')
local M = {}

local RUBBER_MAT, METAL_NAME = 4, 'METAL'
local sw                            -- wheel index -> { { orig, msc } } once built
local stageOf = {}                  -- wheel index -> the stage on show
local metalOf = {}                  -- wheel index -> true while its tread nodes are METAL
local disabled = false

local function tyreMeshes(wd)       -- the tyre flexbody meshes of one wheel: groups like tire_FL, ending in the wheel's name
  local out, name = {}, tostring(wd.name or '')
  for _, fb in pairs(v.data.flexbodies or {}) do
    for _, g in ipairs(type(fb.group) == 'table' and fb.group or { fb.group }) do
      g = tostring(g)
      if fb.mesh and g:find('tire', 1, true) and name ~= '' and g:sub(-#name) == name then out[fb.mesh] = true end
    end
  end
  return out
end

local function build()
  sw = {}
  for wi, wd in pairs(wheels.wheels or {}) do
    local want, list = tyreMeshes(wd), {}
    if next(want) then
      for _, orig in ipairs(NAMES) do
        for mesh in tostring(obj:getMeshesContainingMaterial(orig) or ''):gmatch('%S+') do
          if want[mesh] then
            local msc = obj:getSwitchableMaterial(orig, orig, mesh)
            if msc and msc >= 0 then list[#list + 1] = { orig = orig, msc = msc } end
          end
        end
      end
    end
    sw[wi] = list
  end
end

local function setMetal(wi, on)
  local wd = wheels.wheels[wi]
  if not (wd and wd.treadNodes) or (metalOf[wi] or false) == on then return end
  local id = on and (particles.getMaterialIDByName(particles.materials or v.data.materials, METAL_NAME) or 2) or RUBBER_MAT
  for _, cid in ipairs(wd.treadNodes) do obj:setNodeMaterial(cid, id) end
  metalOf[wi] = on
end

-- stage 0 puts the car's own material back; wear on a wheel that has no tyre mesh we know leaves the look alone
function M.set(wi, stage)
  if disabled then return end
  if not sw then build() end
  stage = math.max(0, math.min(5, math.floor(tonumber(stage) or 0)))
  if stageOf[wi] == stage then return end
  stageOf[wi] = stage
  for _, s in ipairs(sw[wi] or {}) do
    if stage == 0 then obj:resetMaterials(s.msc) else obj:switchMaterial(s.msc, 'csfx_' .. s.orig .. '_s' .. stage) end
  end
  pcall(setMetal, wi, stage >= 5)
end

function M.stages() local t = {} for wi, s in pairs(stageOf) do t[#t + 1] = wi .. '=' .. s end table.sort(t) return table.concat(t, ' ') end
function M.info()       -- for game tests: per wheel the switches found (original material, switch id); empty means no tyre mesh was matched
  if not sw then build() end
  local t = {}
  for wi, l in pairs(sw) do local p = {} for _, s in ipairs(l) do p[#p + 1] = s.orig .. '#' .. s.msc end t[#t + 1] = wi .. ':' .. table.concat(p, ',') end
  table.sort(t)
  return table.concat(t, ' ')
end
function M.setEnabled(on) disabled = not on if disabled then M.restore() end end

function M.restore()
  for wi in pairs(stageOf) do pcall(M.set, wi, 0) end
  stageOf = {}
end
function M.onReset() M.restore() end
function M.onExtensionUnloaded() pcall(M.restore) end

return M
