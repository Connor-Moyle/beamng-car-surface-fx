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

-- The tyre flexbodies carry no group in the vehicle data (the Covet's are tire_01a_13x5_23, ..D, ..DD, ..DDD with group = nil), so a wheel's tyre mesh is found, in turn, by: a group
-- ending in the wheel's name; node lists that hold the wheel's hub node; or, as the last resort, the order (the k-th tyre mesh of the list belongs to the k-th wheel by index: the order the
-- jbeam lists them, FR FL RR RL, checked on the Covet). shortcut: the order is a guess when no group or nodes exist, check the look on a new car.
local function tyreList()
  local out = {}
  for k, fb in ipairs(v.data.flexbodies or {}) do if fb.mesh and tostring(fb.mesh):find('tire', 1, true) then out[#out + 1] = fb end end
  return out
end

local function hasNode(fb, id)
  for _, key in ipairs({ 'nodes', 'cids' }) do
    if type(fb[key]) == 'table' then for _, n in pairs(fb[key]) do if n == id then return true end end end
  end
  return false
end

local function wheelOrder()
  local ks = {}
  for wi in pairs(wheels.wheels or {}) do ks[#ks + 1] = wi end
  table.sort(ks)
  return ks
end

local function tyreMeshes(wd, wi)
  local out, name, tl = {}, tostring(wd.name or ''), tyreList()
  for _, fb in ipairs(tl) do
    for _, g in ipairs(type(fb.group) == 'table' and fb.group or { fb.group or false }) do
      g = tostring(g)
      if g:find('tire', 1, true) and name ~= '' and g:sub(-#name) == name then out[fb.mesh] = true end
    end
    if wd.node1 and hasNode(fb, wd.node1) then out[fb.mesh] = true end
  end
  if next(out) then return out end
  local ks = wheelOrder()
  if #ks == #tl then for k, key in ipairs(ks) do if key == wi then out[tl[k].mesh] = true end end end
  return out
end

local function build()
  sw = {}
  for wi, wd in pairs(wheels.wheels or {}) do
    local want, list = tyreMeshes(wd, wi), {}
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
  local out = table.concat(t, ' ')
  if not out:find('#', 1, true) then       -- nothing matched: show what the matching saw
    local seen = {}
    for wi, wd in pairs(wheels.wheels or {}) do seen[#seen + 1] = 'wheel ' .. wi .. ' name=' .. tostring(wd.name) end
    for _, fb in ipairs(tyreList()) do
      local keys = {} for k in pairs(fb) do keys[#keys + 1] = tostring(k) end table.sort(keys)
      seen[#seen + 1] = 'fb ' .. tostring(fb.mesh) .. ' keys=' .. table.concat(keys, '/')
    end
    out = out .. ' | ' .. table.concat(seen, '; ')
  end
  return out
end
function M.setEnabled(on) disabled = not on if disabled then M.restore() end end

function M.restore()
  for wi in pairs(stageOf) do pcall(M.set, wi, 0) end
  stageOf = {}
end
function M.onReset() M.restore() end
function M.onExtensionUnloaded() pcall(M.restore) end

return M
