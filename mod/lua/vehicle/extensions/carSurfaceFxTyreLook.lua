-- Car Surface FX, vehicle side: how worn each tyre of this car looks. The tyre module reports a stage per wheel (0 new .. 4 bald, 5 belts); here each wheel's own tyre mesh is switched to the
-- file-defined material csfx_<original>_s<stage> (vehicles/common/carSurfaceFx/stages.materials.json, loaded by the game with the first car, made by tools/make_tyre_stage_materials.py) with the engine's per-mesh switch, the way the glowMap on/off
-- materials switch. The switch itself is made on the game side (carSurfaceFx_tyres.look): called from the car's Lua it has no effect on the screen (found in game); here the meshes of each wheel are found. At the belts the tread nodes become METAL, so the engine's own spark and scrape rules (particles.json, METAL on asphalt) apply.
local NAMES = require('csfx_tyrelook_names')
local M = {}

local RUBBER_MAT, METAL_NAME = 4, 'METAL'
local sw                            -- wheel index -> { { orig, mesh } } once built
local stageOf = {}                  -- wheel index -> the stage on show
local metalOf = {}                  -- wheel index -> true while its tread nodes are METAL
local pinned = {}                  -- wheel index -> true while a test has set its stage by hand (the tyre module's own reports leave it alone)
local disabled = false

-- The tyre flexbodies carry no group in the vehicle data (the Covet's are tire_01a_13x5_23, ..D, ..DD, ..DDD with group = nil), so a wheel's tyre mesh is found by a group ending in the wheel's
-- name, or by the flexbody's node list (_group_nodes) holding the wheel's hub or tread nodes. The mesh order is NOT the wheel order (Covet: ..DD is rear left), so there is no guessing by order:
-- a wheel whose mesh is not found keeps its own look.
local function tyreList()
  local out = {}
  for k, fb in ipairs(v.data.flexbodies or {}) do if fb.mesh and tostring(fb.mesh):find('tire', 1, true) then out[#out + 1] = fb end end
  return out
end

local function hasNode(fb, id)
  for _, key in ipairs({ '_group_nodes', 'nodes', 'cids' }) do
    if type(fb[key]) == 'table' then for _, n in pairs(fb[key]) do if n == id then return true end end end
  end
  return false
end

local function tyreMeshes(wd)
  local out, name, tl = {}, tostring(wd.name or ''), tyreList()
  for _, fb in ipairs(tl) do
    for _, g in ipairs(type(fb.group) == 'table' and fb.group or { fb.group or false }) do
      g = tostring(g)
      if g:find('tire', 1, true) and name ~= '' and g:sub(-#name) == name then out[fb.mesh] = true end
    end
    if wd.node1 and hasNode(fb, wd.node1) then out[fb.mesh] = true end
    for _, cid in ipairs(wd.treadNodes or {}) do if hasNode(fb, cid) then out[fb.mesh] = true break end end
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
            list[#list + 1] = { orig = orig, mesh = mesh }
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
  log('D', 'carSurfaceFxTyreLook', 'wheel ' .. wi .. ' tread nodes ' .. (on and 'METAL' or 'RUBBER') .. ' (' .. #wd.treadNodes .. ' nodes)')
end

-- stage 0 puts the car's own material back; wear on a wheel that has no tyre mesh we know leaves the look alone
function M.set(wi, stage, auto)         -- auto: from the tyre module's reports; a call without it is by hand and holds the stage until restore()
  if disabled or (auto and pinned[wi]) then return end
  if not auto then pinned[wi] = true end
  if not sw then build() end
  stage = math.max(0, math.min(5, math.floor(tonumber(stage) or 0)))
  if stageOf[wi] == stage then return end
  stageOf[wi] = stage
  local pairsOut = {}
  for _, s in ipairs(sw[wi] or {}) do pairsOut[#pairsOut + 1] = string.format('{%q,%q}', s.orig, s.mesh) end
  if #pairsOut > 0 then obj:queueGameEngineLua(string.format('if carSurfaceFx_tyres then carSurfaceFx_tyres.look(%d,%d,%d,{%s}) end', obj:getId(), wi, stage, table.concat(pairsOut, ','))) end
  pcall(setMetal, wi, stage >= 5)
end

function M.stages() local t = {} for wi, s in pairs(stageOf) do t[#t + 1] = wi .. '=' .. s end table.sort(t) return table.concat(t, ' ') end
local function glowSwitches()          -- the switches the engine built at spawn from the glowMap entries our game side added (none: the car loaded before the tyres were on, or the hook did not run)
  local n, ex = 0, {}
  local tr = v.data._materials and v.data._materials.triggers or {}
  for _, t in pairs(tr) do
    if t.on and tostring(t.on):find('^csfx_') then n = n + 1 if #ex < 4 then ex[#ex + 1] = tostring(t.orgMat) .. '@' .. tostring(t.mesh) .. '#' .. tostring(t.msc) end end
  end
  return 'glow=' .. n .. (n > 0 and (' [' .. table.concat(ex, ' ') .. ']') or '')
end
function M.info()       -- for game tests: per wheel the switches found (original material, switch id); empty means no tyre mesh was matched
  if not sw then build() end
  local t = {}
  for wi, l in pairs(sw) do local p = {} for _, s in ipairs(l) do p[#p + 1] = s.orig .. '@' .. s.mesh end t[#t + 1] = wi .. ':' .. table.concat(p, ',') end
  table.sort(t)
  local out = table.concat(t, ' ')
  local matched = out:find('@', 1, true)
  out = out .. ' ' .. glowSwitches()
  if not matched then       -- nothing matched: show what the matching saw
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
  stageOf, pinned = {}, {}
end
function M.onReset() M.restore() end
function M.onExtensionUnloaded() pcall(M.restore) end

return M
