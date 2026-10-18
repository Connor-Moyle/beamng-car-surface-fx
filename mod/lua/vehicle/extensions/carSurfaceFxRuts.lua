-- Car Surface FX, vehicle side: wheel ruts (port P4). Twelve times a second each wheel that carries weight on soft ground (mud, snow, sand, dirt, gravel) reports a sample of its path - where
-- the tyre touches, which ground, how much load, how much it spins - every `step` metres, to the GE side (carSurfaceFx_ruts.sample), which decides how deep a rut that is and draws it.
-- The ground comes from the contact material id by the game's own material names (particles.json), like the ground marks; a map's own ground materials arrive through setMaterials.
local M = {}
local abs, min, max, sqrt = math.abs, math.min, math.max, math.sqrt

local INTERVAL = 0.08
local MIN_LOAD = 150                           -- N on the wheel below which nothing is pressed
local MIN_SPEED = 0.5                          -- m/s: a car standing still presses no new rut

local emit = false
local step = 0.6
local minLoad = MIN_LOAD
local custom = {}                              -- a map's own collision type id -> kind
local byName = {}                              -- id -> kind, from the game's material names
local built = false
local forced
local timer = 0
local lastPos = {}                             -- wheel -> { x, y } of the last sample
local out = {}

-- the game's material name -> a ground that takes a rut (nil = it does not)
local function nameToKind(nm)
  nm = tostring(nm):lower()
  if nm:find('snow') then return 'snow' end
  if nm:find('mud') then return 'mud' end
  if nm:find('sand') then return 'sand' end
  if nm:find('gravel') or nm:find('scree') then return 'gravel' end
  if nm:find('dirt') or nm:find('dust') then return 'dirt' end
  return nil
end
M.nameToKind = nameToKind

local function buildNames()
  built = true
  byName = {}
  pcall(function()
    if particles and particles.getMaterialsParticlesTable then
      for id, m in pairs(particles.getMaterialsParticlesTable()) do
        local k = m and m.name and nameToKind(m.name)
        if k then byName[id] = k end
      end
    end
  end)
end

local function contact(wd)
  local p1 = obj:getAbsNodePosition(wd.node1)
  local x, y, z = p1.x, p1.y, p1.z
  if wd.node2 then local p2 = obj:getAbsNodePosition(wd.node2) x, y, z = (x + p2.x) * 0.5, (y + p2.y) * 0.5, (z + p2.z) * 0.5 end
  return x, y, z - (wd.radius or 0.34)
end

local function frame()
  if not emit or not wheels or not wheels.wheels then return end
  if not built then buildNames() end
  local v = obj:getVelocity()
  local speed = sqrt(v.x * v.x + v.y * v.y)
  local n = 0
  for wi, wd in pairs(wheels.wheels) do
    local load = wd.downForce or 0
    if load >= minLoad and speed >= MIN_SPEED and not wd.isTireDeflated then
      local mat = wd.contactMaterialID1 or 0
      if mat == 4 then mat = wd.contactMaterialID2 or 0 end                  -- the tyre's own material is rubber (4); the ground is the other one
      local kind = forced or custom[mat] or byName[mat]
      if kind and kind ~= 'grass' and kind ~= 'tarmac' and kind ~= 'ice' then
        local x, y, z = contact(wd)
        local lp = lastPos[wi]
        if not lp or (x - lp[1]) ^ 2 + (y - lp[2]) ^ 2 >= step * step then
          lastPos[wi] = { x, y }
          n = n + 1
          out[n] = string.format('carSurfaceFx_ruts.sample(%d,%d,%.2f,%.2f,%.2f,"%s",%.0f,%.2f)', obj:getId(), wi, x, y, z, kind, load, abs(wd.lastSlip or 0))
        end
      else
        lastPos[wi] = nil
      end
    else
      lastPos[wi] = nil
    end
  end
  if n > 0 then obj:queueGameEngineLua('if carSurfaceFx_ruts then ' .. table.concat(out, ' ', 1, n) .. ' end') end
end

function M.setConfig(on, stepM, load)
  emit = on and true or false
  if stepM then step = stepM end
  if load then minLoad = load end
  if not emit then lastPos = {} end
end
function M.setMaterials(idToKind)
  custom = {}
  if type(idToKind) == 'table' then for id, k in pairs(idToKind) do if k ~= 'tarmac' and k ~= 'grass' and k ~= 'ice' then custom[id] = k end end end
end
function M.force(kind) forced = kind end                       -- a test: every loaded wheel presses this ground

function M.onExtensionLoaded() built = false end
function M.updateGFX(dt)
  timer = timer + (dt or 0)
  if timer < INTERVAL then return end
  timer = 0
  pcall(frame)                                                -- our code never gets to disable the vehicle
end
function M.onReset() lastPos = {} built = false end
function M.onExtensionUnloaded() lastPos = {} end

return M
