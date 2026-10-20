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

-- how many marks one impact leaves: the hardest few of its contacts, more for a harder hit (1 at the minimum, one more for every doubling of the energy, 8 at most)
function M.markBudget(maxEnergy, minEnergy)
  minEnergy = math.max(1, tonumber(minEnergy) or 4)
  local e = tonumber(maxEnergy) or 0
  if e < minEnergy then return 0 end
  return clamp(1 + math.floor(math.log(e / minEnergy) / math.log(2)), 1, 8)
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

-- the radius of the dent in metres: 4 cm for a tap to 14 cm for a crease, times the amount setting
function M.radius(sev, amount)
  return (0.04 + 0.10 * clamp(tonumber(sev) or 0, 0, 1)) * clamp(tonumber(amount) or 1, 0.3, 3)
end

-- the kind of mark a panel takes. info = { materialName, partName, nodeMaterial } (any may be nil). This slice knows metal only; the rest of the design (carbon, fibreglass, plastic)
-- goes in this one function. Returns the kind, or nil when the node is not a body panel (glass).
local NODE = { METAL = 2, PLASTIC = 3, RUBBER = 4, GLASS = 5 }
M.NODE = NODE
M.KINDS = { metal = true, plastic = true, fibreglass = true, carbon = true }
function M.kindOf(info)
  local nm = info and info.nodeMaterial
  if nm == NODE.GLASS then return nil end
  if nm == NODE.PLASTIC or nm == NODE.RUBBER then return 'plastic' end      -- (rubber: bumper covers and trim; the car side keeps the tyres out)                 -- (fibreglass and carbon are known only from the panel's material name, which the API takes as `kind`)
  return 'metal'                                                  -- the fallback of the design
end

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
