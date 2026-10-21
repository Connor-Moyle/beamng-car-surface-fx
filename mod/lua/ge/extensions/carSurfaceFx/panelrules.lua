-- Car Surface FX: panel damage, the rules (pure, tested in tests/panelrules_test.lua; see docs/PANEL_DAMAGE.md). A hit on a body panel is drawn as a dent in the paint canvas.
-- This first slice: metal dents only. The material lookup is a stub with the fallback of the design (metal).
local M = {}

function M.defaults()
  return { enabled = false, metal = true, plastic = true, fibreglass = true, carbon = true, amount = 1.0, minEnergy = 4, maxMarks = 40 }
end

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
M.clamp = clamp

-- the effective mass (kg) a body node hits with: the car's mass shared over its nodes, times a few for the neighbours that move with it
function M.effectiveMass(mass, nodes)
  mass, nodes = tonumber(mass) or 0, tonumber(nodes) or 0
  if mass <= 0 or nodes <= 0 then return 20 end
  return clamp(mass / nodes * 4, 5, 60)
end

-- how many marks one impact leaves: 1 at the minimum, two more for every doubling of the energy (5 at 10 km/h, 9 at 20, 13 at 40), 16 at most; the hardest contacts get them, scattered round when there are fewer contacts than that
function M.markBudget(maxEnergy, minEnergy)
  minEnergy = math.max(1, tonumber(minEnergy) or 4)
  local e = tonumber(maxEnergy) or 0
  if e < minEnergy then return 0 end
  return clamp(1 + math.floor(2 * math.log(e / minEnergy) / math.log(2)), 1, 16)
end

-- the speed a hit counts with (m/s): the change of the car's own speed over the last 0.6 s when it is a real change (1 m/s or more: a crash, a wall stop, being hit while parked), else
-- the node's perpendicular speed capped at 1 m/s (against a resting contact that speed jitters up to 8 m/s, so on its own it called a 3 km/h tap a crash; 1 m/s is 2.5 J, under the minimum)
function M.closingSpeed(perp, dv)
  dv = tonumber(dv)
  if dv and dv >= 1 then return dv end
  return math.min(math.abs(tonumber(perp) or 0), 1)
end

-- joules: the energy of the hit node's speed into the panel, or what the normal force gives over a small give (2 mm), whichever is more. A calibration that sets size and
-- thresholds only; the probe (docs/PANEL_DAMAGE.md section 7) measures the real numbers.
function M.energy(perp, normalForce, mass, nodes)
  local v = math.abs(tonumber(perp) or 0)
  local byV = 0.5 * M.effectiveMass(mass, nodes) * v * v
  local byF = math.max(0, tonumber(normalForce) or 0) * 0.002
  return math.max(byV, byF)
end

-- 0 (barely a mark) .. 1 (a deep crease), from the energy over the minimum: a hit at the minimum is 0.1, SPAN times the minimum is 1, smoothly between (with the energy of a car's speed
-- change: about 5 J at 5 km/h (faint), 20 J at 10 km/h (small), 80 J at 20 km/h, 300 J at 40 km/h (1)). The minimum of 4 J leaves the resting contact below it
M.SPAN = 75
function M.severity(energy, minEnergy)
  minEnergy = math.max(1, tonumber(minEnergy) or 4)
  if (tonumber(energy) or 0) < minEnergy then return 0 end
  return clamp(0.1 + 0.9 * math.log(energy / minEnergy) / math.log(M.SPAN), 0.1, 1)
end

-- how far (metres) the extra marks of a hard hit scatter from a contact: 5 cm to 30 cm
function M.spread(sev) return 0.05 + 0.25 * clamp(tonumber(sev) or 0, 0, 1) end

-- the radius of a mark in metres: 4 cm for a tap to 22 cm for a crease, times the amount setting
function M.radius(sev, amount)
  return (0.04 + 0.18 * clamp(tonumber(sev) or 0, 0, 1)) * clamp(tonumber(amount) or 1, 0.3, 3)
end

-- The kind of mark a panel takes. info = { partName, nodeMaterial } (any may be nil). Returns the kind, or nil when the node is not a body panel (glass).
-- Order: glass is nothing; the part the node belongs to (jbeam partOrigin) says carbon or fibreglass by its name, and plastic for the parts that are plastic whatever the node says
-- (mirrors, flares, spoilers, wings, grilles, splitters); then the node material (plastic and rubber trim are plastic); the fallback is metal.
-- The words come from tools/list_panel_parts.py run on the stock cars: carbon is the drag and stock-car wings, fibreglass the hoods and tailgates of the Covet and the Midsize,
-- the plastic words are the trim parts that every car has. A bumper is not in the list: a steel bumper bar is metal; a bumper cover has plastic or rubber nodes (node material below).
local NODE = { METAL = 2, PLASTIC = 3, RUBBER = 4, GLASS = 5 }
M.NODE = NODE
M.KINDS = { metal = true, plastic = true, fibreglass = true, carbon = true }
M.PART_CARBON = { 'carbon' }
M.PART_FIBREGLASS = { 'fiberglass', 'fibreglass', 'glassfiber' }
M.PART_PLASTIC = { 'mirror', 'flare', 'spoiler', 'splitter', 'bigwing', 'grille', 'fascia', 'diffuser', 'sideskirt', 'valance' }
M.PART_NOT_PLASTIC = { 'bullbar', 'light', 'badge', 'lettering', 'antenna', 'bracket', 'guard', 'control', 'rail', 'step', 'flipramp' }     -- (a word above inside one of these is not a plastic panel)
local function has(name, words)
  for _, w in ipairs(words) do if name:find(w, 1, true) then return true end end
  return false
end
-- the kind a part name says, or nil (the node material then decides)
function M.kindOfPart(part)
  if type(part) ~= 'string' or part == '' then return nil end
  local name = part:lower()
  if has(name, M.PART_CARBON) then return 'carbon' end
  if has(name, M.PART_FIBREGLASS) then return 'fibreglass' end
  if has(name, M.PART_PLASTIC) and not has(name, M.PART_NOT_PLASTIC) then return 'plastic' end
  return nil
end
function M.kindOf(info)
  local nm = info and info.nodeMaterial
  if nm == NODE.GLASS then return nil end
  local byPart = info and M.kindOfPart(info.partName)
  if byPart then return byPart end
  if nm == NODE.PLASTIC or nm == NODE.RUBBER then return 'plastic' end      -- (rubber: bumper covers and trim; the car side keeps the tyres out)
  return 'metal'                                                  -- the fallback of the design
end

-- The node of a list of mapped points nearest to (x, y, z), at most maxDist away: points = { { x, y, z, cid } }. For a node the paint map does not know (a bumper cover or other part
-- the paint layer does not paint) the mark goes on the nearest painted spot: it shows on the body panel beside the part that was hit.
function M.nearestPoint(points, x, y, z, maxDist)
  local best, bd = nil, (maxDist or 0.7) ^ 2
  for i = 1, #points do
    local p = points[i]
    local dx, dy, dz = p[1] - x, p[2] - y, p[3] - z
    local d2 = dx * dx + dy * dy + dz * dz
    if d2 < bd then best, bd = p[4], d2 end
  end
  return best, best and math.sqrt(bd) or nil
end
M.NEAR_M = 0.7

-- the light on the car, in the car's own left / back / up components: from above and a little ahead (back is negative ahead). The real sun direction is a later refinement
M.LIGHT = { 0, -0.4, 1 }

-- whether a hit becomes a mark now: the master, the kind's switch, the energy over the minimum, and the per-node cooldown (t, readyAt)
function M.accept(cfg, kind, energy, t, readyAt)
  if not (cfg and cfg.enabled) then return false end
  if not M.KINDS[kind] or cfg[kind] ~= true then return false end
  if (energy or 0) < cfg.minEnergy then return false end
  if (readyAt or 0) > (t or 0) then return false end
  return true
end

return M
