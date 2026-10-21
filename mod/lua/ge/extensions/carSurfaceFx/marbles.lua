-- Car Surface FX: rubber marbles on the road (Connor). The rubber a long burnout throws off collects as patches on the ground (csfx_tyrerules marble*): the patches are
-- kept here, drawn as dark decals through the marks decal route (no meshes, so no gpugate), pushed to the cars (the car module slows a tyre rolling over one and reports a scuff),
-- and a hot one can burn (a glowing patch; it never lights a car). Off by default (cfg.marbles.enabled); tyres.lua owns the calls.
local M = {}
local R = require('csfx_tyrerules')

local list, nextId, clock, dirty = {}, 0, 0, false
local pools = {}                                  -- texture -> { n = count, e = array of decal entries }
local TEX = { 'art/decals/impacts/chip_1.png', 'art/decals/impacts/chip_2.png' }
local GLOW = 'art/decals/fluids/puddle_1.png'
local DEPTH, MAX_BITS, CULL = 1.5, 260, 80          -- decal depth, the most decals drawn a frame, the camera distance beyond which nothing is drawn

function M.list() return list end
function M.count() return #list end
function M.clear() for i = #list, 1, -1 do list[i] = nil end dirty = true end

function M.add(cfg, g, T, x, y, z)
  if not (cfg.marbles.enabled and x and y) then return nil end
  local p = R.marbleAdd(list, x, y, z or 0, g, T or 20, clock, cfg)
  if not p.id then nextId = nextId + 1 p.id = nextId end
  dirty = true
  return p
end

function M.scuff(id, frac)
  for _, p in ipairs(list) do if p.id == id then R.marbleScuff(p, frac) dirty = true return true end end
  return false
end

-- one frame: the patches cool, decay and burn; returns the number burning
function M.step(cfg, dt, ambient, wet)
  clock = clock + dt
  if not cfg.marbles.enabled then if #list > 0 then M.clear() end return 0 end
  local n = #list
  local burning = R.marbleStep(list, dt, ambient or 20, wet or 0, cfg)
  if #list ~= n or burning > 0 then dirty = true end
  return burning
end

-- the list for a car as a Lua table literal, { {x,y,g,id}, ... }; `due` is true when something changed since the last time
function M.pack(force)
  if not (dirty or force) then return nil end
  dirty = false
  local o = {}
  for _, p in ipairs(list) do o[#o + 1] = string.format('{%.2f,%.2f,%.1f,%d}', p.x, p.y, p.g, p.id or 0) end
  return '{' .. table.concat(o, ',') .. '}'
end

-- two cached colours (the dark bits) and a few of the glow, so a frame allocates nothing
local DARK, GLOWC, SMEAR
local function glowColour(phase)
  GLOWC = GLOWC or {}
  local i = math.floor((phase % 1) * 8) + 1
  if not GLOWC[i] then local s = math.sin((i - 1) / 8 * 6.283) GLOWC[i] = ColorF(1, 0.30 + 0.15 * s, 0.04, 0.55 + 0.25 * s) end
  return GLOWC[i]
end

local function hash(a, b) local s = math.sin(a * 12.9898 + b * 78.233) * 43758.5453 return s - math.floor(s) end

-- the decals of this frame: dark bits scattered over each patch within CULL of the camera, a glow under a burning one. One engine call draws decals of ONE texture, so each texture
-- has its own pool (a plain array, as the engine call wants); `draw(array, n)` is that call (marks.drawBatch). Returns the number of decals.
local function slot(tex, k)
  local pl = pools[tex]
  if not pl then pl = { n = 0, e = {} } pools[tex] = pl end
  pl.n = pl.n + 1
  local e = pl.e[pl.n]
  if not e then
    e = { texture = tex, position = vec3(0, 0, 0), forwardVec = vec3(1, 0, 0), color = ColorF(0.04, 0.04, 0.04, 0.9), scale = vec3(0.2, 0.2, DEPTH), fadeStart = CULL * 0.8, fadeEnd = CULL }
    pl.e[pl.n] = e
  end
  return e
end

function M.draw(cfg, camX, camY, draw)
  if not (cfg.marbles.enabled and #list > 0) then return 0 end
  for _, pl in pairs(pools) do pl.n = 0 end
  local total = 0
  for _, p in ipairs(list) do
    if total >= MAX_BITS then break end
    if not camX or (p.x - camX) ^ 2 + (p.y - camY) ^ 2 <= CULL * CULL then
      local r = R.marbleRadius(p.g, cfg)
      local bits = math.max(4, math.min(48, math.floor(p.g / 3) + 6))      -- (a 400 g patch is 48 bits over its 1.5 m: a heap, not a few specks)
      if total < MAX_BITS then          -- a dark smear under the bits so a patch reads as one
        total = total + 1
        local e = slot(GLOW)
        e.position:set(p.x, p.y, p.z)
        e.forwardVec:set(hash(p.id or 0, 1), hash(p.id or 0, 2), 0)
        e.scale:set(r * 1.6, r * 1.6, DEPTH)
        SMEAR = SMEAR or ColorF(0.02, 0.02, 0.02, 0.45)
        e.color = SMEAR
      end
      for i = 1, bits do
        if total >= MAX_BITS then break end
        total = total + 1
        local e = slot(TEX[1 + (i + (p.id or 0)) % #TEX])
        local a, d, ang = hash(p.id or 0, i) * 6.283, math.sqrt(hash(p.id or 0, i + 50)) * r, hash(p.id or 0, i + 99) * 6.283
        local s = 0.14 + 0.2 * hash(p.id or 0, i + 7)
        e.position:set(p.x + math.cos(a) * d, p.y + math.sin(a) * d, p.z)
        e.forwardVec:set(math.cos(ang), math.sin(ang), 0)
        e.scale:set(s, s, DEPTH)
        DARK = DARK or ColorF(0.04, 0.04, 0.04, 0.9)
        e.color = DARK
      end
      if ((p.burn or 0) > 0 or (p.T or 0) >= cfg.marbles.glowT) and total < MAX_BITS then   -- (hot rubber glows before and without fire)
        total = total + 1
        local e = slot(GLOW)
        e.position:set(p.x, p.y, p.z)
        e.forwardVec:set(1, 0, 0)
        e.scale:set(r * 2, r * 2, DEPTH)
        e.color = glowColour(clock * 1.7 + (p.id or 0) * 0.37)       -- a pulse: eight steps round the cycle
      end
    end
  end
  for _, pl in pairs(pools) do if pl.n > 0 then draw(pl.e, pl.n) end end
  return total
end

return M
