-- Car Surface FX: the rules of the grass flattening (carSurfaceFx/grass.lua), as plain functions so they are tested outside the game.
-- The game has a surface mask that its ground cover shader reads (flatten, bend direction, cut per spot) and the engine global SurfaceMaskClipmap that paints it
-- with circle and line stamps (see docs/GRASS_FLATTENING.md). These rules decide what to stamp: how wide, how strong, where, and when old trails are let go.
local M = {}

M.DEFAULTS = {
  enabled = false,          -- grass bends under the wheels
  strength = 1,             -- 0..1: how flat (the game's own stamper uses 1)
  widthScale = 1,           -- x the tyre width x 1.6
  wheelspinCut = true,      -- a spinning or skidding wheel tears the grass out (bare earth)
  traffic = true,           -- other cars near the player bend grass too
  distance = 60,            -- m from the player, for other cars
  maxCars = 6,              -- at most this many other cars at once
  clearOnLevel = true,      -- the trails are cleared when a level loads
  clearAfterMin = 0,        -- 0: trails stay; N: a trail is let go N minutes after it was made (the mask cannot fade: it is cleared and the recent trails stamped again)
}

local function clamp(v, lo, hi) v = tonumber(v) or lo if v < lo then return lo elseif v > hi then return hi end return v end
M.clamp = clamp

-- the settings table from a loaded one (unknown keys dropped, bad values back to the default, numbers clamped)
function M.sanitize(t)
  local d, out = M.DEFAULTS, {}
  t = type(t) == 'table' and t or {}
  for k, dv in pairs(d) do
    local v = t[k]
    if type(dv) == 'boolean' then
      if type(v) == 'boolean' then out[k] = v else out[k] = dv end
    else out[k] = tonumber(v) or dv end
  end
  out.strength = clamp(out.strength, 0, 1)
  out.widthScale = clamp(out.widthScale, 0.3, 3)
  out.distance = clamp(out.distance, 10, 150)
  out.maxCars = math.floor(clamp(out.maxCars, 0, 20))
  out.clearAfterMin = clamp(out.clearAfterMin, 0, 120)
  return out
end

-- the width of the stamp for a wheel whose two axle nodes are `axle` metres apart (nil: unknown, a car's usual tyre)
function M.stampWidth(axle, scale)
  return clamp((tonumber(axle) or 0.25) * 1.6 * (scale or 1), 0.35, 1.4)
end

-- how flat: more with speed (a fast car presses the grass harder and further), times the setting
function M.flatten(speed, strength)
  return clamp((0.6 + 0.4 * clamp((tonumber(speed) or 0) / 25, 0, 1)) * (strength or 1), 0, 1)
end

-- the cut: the shader removes a blade only from 0.95 up (it fades out between 0.95 and 0.99), so below that a stamp only bends. A wheel that spins or skids (the share of
-- the last reading spent slipping) tears the grass out; otherwise a stamp keeps under the threshold.
function M.mark(slipShare, cutting)
  if cutting and (tonumber(slipShare) or 0) >= 0.35 then return 1 end
  return 0.5
end

-- is this terrain material a grass layer? (by name, as the game's lawn mower decides; `extra` more name parts)
function M.isGrassName(name, extra)
  local n = tostring(name or ''):lower()
  if n:find('grass', 1, true) or n:find('meadow', 1, true) or n:find('lawn', 1, true) or n:find('turf', 1, true) then return true end
  for _, part in ipairs(extra or {}) do if part ~= '' and n:find(tostring(part):lower(), 1, true) then return true end end
  return false
end

-- is a wheel's step worth a stamp: it moved at least `minSq` (squared metres) and did not jump (a teleport, a reset: `maxSq`)
function M.step(dx, dy, dz, minSq, maxSq)
  local d = dx * dx + dy * dy + dz * dz
  if d > (maxSq or 100) then return 'jump' end
  if d > (minSq or 0.04) then return 'stamp' end
  return 'still'
end

-- ---- the log of stamps, for the "let trails go after N minutes" policy --------------------------------------------------------------------------------------
-- log = { n = count, [i] = { t, x1, y1, x2, y2, w, f, m } }, a ring of at most `cap` stamps; a circle has x2 == nil
function M.logNew(cap) return { n = 0, cap = cap or 3000, head = 0 } end

function M.logAdd(log, t, x1, y1, x2, y2, w, f, m)
  log.head = log.head % log.cap + 1
  local e = log[log.head]
  if not e then e = {} log[log.head] = e end
  e.t, e.x1, e.y1, e.x2, e.y2, e.w, e.f, e.m = t, x1, y1, x2, y2, w, f, m
  log.n = math.min(log.cap, log.n + 1)
end

-- the stamps younger than `lifetime` seconds within `radius` of (px, py), oldest first, at most `max`
function M.logRecent(log, now, lifetime, px, py, radius, max)
  local out = {}
  local r2 = radius * radius
  for i = 1, log.n do
    local idx = (log.head - log.n + i - 1) % log.cap + 1
    local e = log[idx]
    if e and now - e.t < lifetime then
      local dx, dy = e.x1 - px, e.y1 - py
      if dx * dx + dy * dy <= r2 then out[#out + 1] = e end
    end
  end
  if max and #out > max then
    local keep = {}
    for i = #out - max + 1, #out do keep[#keep + 1] = out[i] end
    return keep
  end
  return out
end

-- is a purge due: the oldest stamp is older than the lifetime (and `every` seconds passed since the last)
function M.purgeDue(log, now, lifetime, lastPurge, every)
  if lifetime <= 0 or log.n == 0 or now - lastPurge < every then return false end
  local oldest = log[(log.head - log.n) % log.cap + 1]
  return oldest ~= nil and now - oldest.t >= lifetime
end

return M
