-- Car Surface FX: panel damage, the rules (pure, tested in tests/panelrules_test.lua; see docs/PANEL_DAMAGE.md). A hit on a body panel is drawn as a dent in the paint canvas.
-- This first slice: metal dents only. The material lookup is a stub with the fallback of the design (metal).
local M = {}

function M.defaults()
  return { enabled = false, metal = true, amount = 1.0, minEnergy = 60, maxMarks = 40 }
end

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
M.clamp = clamp

-- the effective mass (kg) a body node hits with: the car's mass shared over its nodes, times a few for the neighbours that move with it
function M.effectiveMass(mass, nodes)
  mass, nodes = tonumber(mass) or 0, tonumber(nodes) or 0
  if mass <= 0 or nodes <= 0 then return 20 end
  return clamp(mass / nodes * 4, 5, 60)
end

-- joules: the energy of the hit node's speed into the panel, or what the normal force gives over a small give (2 mm), whichever is more. A calibration that sets size and
-- thresholds only; the probe (docs/PANEL_DAMAGE.md section 7) measures the real numbers.
function M.energy(perp, normalForce, mass, nodes)
  local v = math.abs(tonumber(perp) or 0)
  local byV = 0.5 * M.effectiveMass(mass, nodes) * v * v
  local byF = math.max(0, tonumber(normalForce) or 0) * 0.002
  return math.max(byV, byF)
end

-- 0 (barely a mark) .. 1 (a deep crease), from the energy over the minimum: a tap at the minimum is 0.1, 20 times the minimum is 1
function M.severity(energy, minEnergy)
  minEnergy = math.max(1, tonumber(minEnergy) or 60)
  if (tonumber(energy) or 0) < minEnergy then return 0 end
  return clamp(0.1 + 0.9 * math.log(energy / minEnergy) / math.log(20), 0.1, 1)
end

-- the radius of the dent in metres: 4 cm for a tap to 14 cm for a crease, times the amount setting
function M.radius(sev, amount)
  return (0.04 + 0.10 * clamp(tonumber(sev) or 0, 0, 1)) * clamp(tonumber(amount) or 1, 0.3, 3)
end

-- the kind of mark a panel takes. info = { materialName, partName, nodeMaterial } (any may be nil). This slice knows metal only; the rest of the design (carbon, fibreglass, plastic)
-- goes in this one function. Returns the kind, or nil when that kind is not built yet or the node is not a body panel (rubber, glass).
local NODE = { METAL = 2, PLASTIC = 3, RUBBER = 4, GLASS = 5 }
M.NODE = NODE
function M.kindOf(info)
  local nm = info and info.nodeMaterial
  if nm == NODE.RUBBER or nm == NODE.GLASS then return nil end
  return 'metal'                                                  -- (the fallback of the design: unknown or plastic is drawn as metal until the plastic kind exists)
end

-- the light on the car, in the car's own left / back / up components: from above and a little ahead (back is negative ahead). The real sun direction is a later refinement
M.LIGHT = { 0, -0.4, 1 }

-- whether a hit becomes a mark now: the master, the kind's switch, the energy over the minimum, and the per-node cooldown (t, readyAt)
function M.accept(cfg, kind, energy, t, readyAt)
  if not (cfg and cfg.enabled) then return false end
  if kind == 'metal' and not cfg.metal then return false end
  if kind ~= 'metal' then return false end
  if (energy or 0) < cfg.minEnergy then return false end
  if (readyAt or 0) > (t or 0) then return false end
  return true
end

return M
