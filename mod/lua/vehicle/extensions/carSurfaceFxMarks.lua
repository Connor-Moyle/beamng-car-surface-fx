-- Car Surface FX, vehicle side: the wheel marks (ported from Surface FX, same author). Every frame each wheel that carries weight on a surface we know sends its steps to
-- the GE side (carSurfaceFx_marks.addSegment): a SKID step while it spins or slides, a faint TRACK step otherwise. The step reaches forward toward the tyre by a gap that grows
-- with speed, so the mark keeps up at speed instead of trailing behind the wheel. The surface comes from the contact material id, by the material's name.
local M = {}
local abs, min, sqrt = math.abs, math.min, math.sqrt

local SLIP_THRESHOLD = 1.5
local SIDE_SLIP_THRESHOLD = 0.8
local MIN_DOWNFORCE = 80
local SKID_MIN_SEGMENT = 0.10                  -- how far apart skid points are (m)
local TRACK_MIN_SEGMENT = 0.22                 -- tracks are sparser, they are subtle
local MAX_SEGMENT = 6.0                        -- a jump bigger than this is a teleport
local RUBBER_MAT = 4                           -- the tyre's own material id; the ground is the other one

local SURF = { [14] = 'dirt', [15] = 'dirt', [16] = 'sand', [17] = 'sand', [18] = 'mud', [19] = 'gravel', [20] = 'grass', [21] = 'ice' }   -- old fixed ids, if the names fail
local customIdType = {}                        -- anything a map's config adds (id -> surface)
local nameSurf = {}                            -- id -> surface, from the game's material names

-- a material name -> one of the surfaces (nil = not one of ours)
local function nameToType(nm)
  nm = tostring(nm):lower()
  if nm:find('snow') then return 'snow' end
  if nm:find('ice') then return 'ice' end
  if nm:find('mud') then return 'mud' end
  if nm:find('sand') then return 'sand' end
  if nm:find('gravel') or nm:find('scree') then return 'gravel' end
  if nm:find('grass') or nm:find('meadow') or nm:find('lawn') then return 'grass' end
  if nm:find('dirt') or nm:find('dust') or nm:find('soil') or nm:find('trail') or nm:find('dry') then return 'dirt' end
  return nil
end
M.nameToType = nameToType

local function buildNameSurf()
  nameSurf = {}
  pcall(function()
    if particles and particles.getMaterialsParticlesTable then
      local mats = particles.getMaterialsParticlesTable()
      if type(mats) == 'table' then
        for id, m in pairs(mats) do
          local typ = m and m.name and nameToType(m.name)
          if typ then nameSurf[id] = typ end
        end
      end
    end
  end)
end

local WHEEL_GAP = 0.12
local emit = false                              -- the GE side switches it on for the cars that mark
local allSurfaces = false                       -- takeover: every surface marks, unknown and hard ones as 'tarmac'
local lastPos = {}
local loaded = false
local out = {}                                  -- the steps of this frame, sent as one command

local function classify(id) return customIdType[id] or nameSurf[id] or SURF[id] end

-- the wheel's contact point in the world: the middle of the axle nodes, down by the radius
local function wheelContact(wd)
  local p1 = obj:getAbsNodePosition(wd.node1)
  local x, y, z = p1.x, p1.y, p1.z
  if wd.node2 then local p2 = obj:getAbsNodePosition(wd.node2) x, y, z = (x + p2.x) * 0.5, (y + p2.y) * 0.5, (z + p2.z) * 0.5 end
  return x, y, z - (wd.radius or 0.34)
end

local function frameUpdate()
  if not emit or not wheels or not wheels.wheels then return end
  local sp, vdx, vdy = 0, 0, 0
  local v = obj:getVelocity()
  sp = sqrt(v.x * v.x + v.y * v.y)
  if sp > 0.1 then vdx, vdy = v.x / sp, v.y / sp end
  local shift = WHEEL_GAP + min(sp * 0.02, 1.0)
  local n = 0
  for wi, wd in pairs(wheels.wheels) do
    if wd and (wd.downForce or 0) >= MIN_DOWNFORCE then
      local slip = (wd.lastSlip or 0) * min((wd.downForce or 0) * 0.1, 1.0)
      local side = abs(wd.lastSideSlip or 0)
      local isSkid = slip >= SLIP_THRESHOLD or side >= SIDE_SLIP_THRESHOLD
      local mat = wd.contactMaterialID1 or 0
      if mat == RUBBER_MAT then mat = wd.contactMaterialID2 or 0 end
      local typ = classify(mat) or (allSurfaces and 'tarmac' or nil)
      if typ then
        local step = isSkid and SKID_MIN_SEGMENT or TRACK_MIN_SEGMENT
        local cx, cy, cz = wheelContact(wd)
        cx, cy = cx + vdx * shift, cy + vdy * shift
        local lp = lastPos[wi]
        if lp then
          local dx, dy = cx - lp[1], cy - lp[2]
          local d = sqrt(dx * dx + dy * dy)
          if d >= step and d <= MAX_SEGMENT then
            local inten = isSkid and min(1.0, slip * 0.07 + side * 0.14) or 0.5
            n = n + 1
            out[n] = string.format('carSurfaceFx_marks.addSegment(%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,"%s",%d,%.3f)', lp[1], lp[2], lp[3], cx, cy, cz, typ, isSkid and 1 or 0, inten)
            lp[1], lp[2], lp[3] = cx, cy, cz
          elseif d > MAX_SEGMENT then
            lp[1], lp[2], lp[3] = cx, cy, cz
          end
        else
          lastPos[wi] = { cx, cy, cz }
        end
      else
        lastPos[wi] = nil                                   -- left the ground we mark: start fresh next time
      end
    else
      lastPos[wi] = nil                                     -- in the air: no line across a jump
    end
  end
  if n > 0 then
    obj:queueGameEngineLua('if carSurfaceFx_marks then ' .. table.concat(out, ' ', 1, n) .. ' end')
  end
end

function M.setConfig(gap, all, on)
  if gap ~= nil then WHEEL_GAP = gap end
  allSurfaces = all and true or false
  emit = on and true or false
  if not emit then lastPos = {} end
end
function M.setMaterials(idToType) customIdType = type(idToType) == 'table' and idToType or {} end

function M.onExtensionLoaded() if not loaded then loaded = true lastPos = {} buildNameSurf() end end
function M.updateGFX() pcall(frameUpdate) end              -- our code never gets to disable the vehicle
function M.onReset() lastPos = {} end
function M.onExtensionUnloaded() loaded = false lastPos = {} end

return M
