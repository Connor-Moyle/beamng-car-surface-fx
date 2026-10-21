-- Ported from Enhanced Skid Marks (Surface FX) by Fatkiwi (the same author), renamed for Car Surface FX.
--[[ ------------------------------------------------------------------------
  carSurfaceFx/scratch.lua  -  GE side: real scratch marks + wheel-arch dirt
  painted onto the car's own paint, on ANY vehicle, with no per-vehicle files.
  by Fatkiwi

  how it works (all confirmed in-game on 0.39.4, not assumed):
    * WHERE: carSurfaceFx/meshuv.lua reads the car's source mesh at spawn and tells
      us where every jbeam node sits on the paint texture, and how a direction
      in car space runs across the texture there.
    * WHAT WE DRAW ON: two live web canvases per car (veh:createUITexture - the
      same thing the dash screens use), named TAG_B and TAG_P. a canvas texture
      is per VEHICLE even though the material is shared, so two of the same
      model each keep their own scratches.
    * HOW IT REACHES THE PAINT: we point the car's own PAINT LAYER at them, live,
      and put it back exactly on the way out (same idea as carSurfaceFx):
        baseColorMap    = TAG_B  starts white (= the "no texture" the layer had),
                                 marks are drawn in their real colour
        colorPaletteMap = TAG_P  starts solid red (= "paint colour 1 everywhere",
                                 what nullcolormaskR was), marks are ERASED from it.
                                 the shader shows the base colour un-tinted wherever
                                 the palette's alpha is gone, so the mark shows in
                                 its own colour and the paint around it is untouched.
      a layer's OPACITY can't be driven by a canvas (the shader reads it only from a
      file texture's red channel - tried, renders solid), which is why this rides on
      the existing paint layer instead of adding one on top.
    * WHEN: carSurfaceFxWear.lua (car side, through carSurfaceFx/bodywear.lua) reports hard sliding body hits and
      wheels rolling on loose ground; everything else happens here.

  limits, on purpose:
    * a paint layer whose palette map is a real texture (a livery, or a car with
      several colour zones like the ETK 800) keeps it - a canvas can't load a .dds
      to redraw it - so there marks can only DARKEN the paint: scratches are drawn
      dark instead of as bare metal. (GBitmap can't convert one either: loading a
      .dds through it crashed the game outright.)
    * a paint layer that already has its own base texture keeps it, so there
      marks only show in the bare base colour.
    * every car sharing a touched material needs the canvases or its paint
      renders garbage, so each one gets them (blank), scratched or not.
    * no source .dae shipped for a vehicle (some mods) = no map = nothing happens.
------------------------------------------------------------------------- --]]

local M = {}
local bodymap = require('carSurfaceFx/bodymap')
local canvasV = require('carSurfaceFx/daeread').canvasV                  -- the .dae's v runs up, the canvas runs down
local logTag = 'carSurfaceFx_scratch'
local DEFAULT_GLOW_NITS = 45000
local TAG_B, TAG_P, TAG_E = '@csfx_base', '@csfx_palette', '@csfx_emis'
local PAGE = 'local://local/vehicles/common/carSurfaceFx/scratch.html'
local PAGE_V = 35                                              -- bumped with every change of scratch.html/.js/paintwater.js: the browser caches pages by their address, a new number loads the new files
local SIZE, FPS = 1024, 10   -- the engine caps a web texture near the screen size: 2048 came back part garbage

local random, sqrt, floor, min, max = math.random, math.sqrt, math.floor, math.min, math.max
local unpack = unpack or table.unpack

local function defaults()
  return {
    enabled  = true,
    colour   = { 0.72, 0.72, 0.70 },                -- bare primer showing through
    opacity  = 0.9,
    markSize = 1.0,                                 -- scratch length multiplier
    dirtEnabled = true,
    dirtColour  = { 0.28, 0.21, 0.14 },
    dirtOpacity = 0.45,
    dirtSize    = 0.045,                            -- splat radius, metres
    dirtRate    = 1.0,
    water       = true,                             -- rain drops running over the paint
    allVehicles = false,                            -- false = just the car you're in (matches Body Dirt)
    dirtGlow    = false,                            -- a third canvas in the paint's emissive slot: the dirt's own colour added as light (the colour map can only darken)
    dirtGlowNits = DEFAULT_GLOW_NITS,
    panelLit    = false,                            -- set by carSurfaceFx while panel damage is on: the lit page is bound too, so marks show on dark paint (not a setting of its own)
  }
end
local settings = defaults()

-- what each car has been marked with, kept GE-side (the canvas pages are write-only for us): scratch lines { x1, y1, x2, y2, width } and dirt splats { x, y, r, opacity, kind }
-- (kind 1 = dust, 2 = mud), quantised and capped, so a car's marks can be saved (getState) and drawn again on a respawned car (restore, and after a mesh rebuild).
local memory, replayAt, nodesAt, nodesSent = {}, {}, {}, {}
local restoredAt = {}                                          -- id -> when marks were put back on a respawned car (a reset right after is ignored)
local MEMORY_CAP = 60
local function mem(id)
  local m = memory[id]
  if not m then m = { marks = {}, splats = {}, dents = {} } memory[id] = m end
  return m
end
local function remember(list, rec)
  list[#list + 1] = rec
  if #list > MEMORY_CAP then table.remove(list, 1) end
end
local function q(x, k) k = k or 1000 return floor(x * k + 0.5) / k end
local MUD, DUST = { 0.20, 0.14, 0.09 }, { 0.50, 0.42, 0.30 }

local cars  = {}     -- vehId -> { building=true } | { none=true } | { lut=, pos=, axes=, wheelPts={} }
local bound = {}     -- material name -> { [layer] = original field values }

-- the settings come from carSurfaceFx (settings.scratch): enabled, colour, opacity, markSize, dirtEnabled, dirtColour, dirtOpacity, dirtSize, dirtRate, allVehicles
function M.configure(t)
  settings = defaults()
  for k, v in pairs(t or {}) do if settings[k] ~= nil then settings[k] = v end end
end
local function active() return settings.enabled or settings.dirtEnabled end
local function litOn() return settings.dirtGlow or settings.panelLit end


-- ---- the car-side reporter (carSurfaceFx/bodywear.lua puts the contact sorting into the cars) ----
-- (a command into every car's Lua once a second was a lot of traffic for nothing: now when the setting changed or every 5 s, and at once for a new car)
local injectedAt = {}      -- vehId -> { at = os.clock(), enabled = }
local function injectVehicle(veh)
  local id, now = veh:getId(), os.clock()
  local i = injectedAt[id]
  if i and i.enabled == settings.enabled and now - i.at < 5 then return end
  if i then i.at, i.enabled = now, settings.enabled else injectedAt[id] = { at = now, enabled = settings.enabled } end
  local bw = rawget(_G, 'carSurfaceFx_bodywear')
  if bw then bw.inject(veh, settings.enabled) end                     -- the car-side body wear (contact sorting) replaces the old detector
end

-- ---- materials ----
local function truthy(v) return v == true or v == 1 or v == '1' or v == 'true' end
local function field(mat, name, layer) return tostring(mat:getField(name, layer) or '') end

-- every paint layer on this car we could draw on: { name=, mat=, layer=, mapTo=, base=bool, pal=bool }
local function paintLayers(veh)
  local out = {}
  for _, nm in ipairs(veh:getMaterialNames() or {}) do
    local mat = scenetree.findObject(nm)
    if mat and tostring(mat:getClassName()):lower() == 'material' and not truthy(mat:getField('translucent', 0)) then
      for layer = 0, (tonumber(mat:getField('activeLayers', 0)) or tonumber(mat.activeLayers) or 1) - 1 do
        local done = bound[nm] and bound[nm][layer]
        local pal, base = done and done.colorPaletteMap or field(mat, 'colorPaletteMap', layer), done and done.baseColorMap or field(mat, 'baseColorMap', layer)
        local inst = truthy(mat:getField('instanceDiffuse', layer))
        -- paint = takes the car's colour, either the old way (instanceDiffuse) or through a palette map
        if inst or (pal ~= '' and truthy(mat:getField('paletteBaseColor', layer))) then
          local mapTo = field(mat, 'mapTo', 0)
          -- a fitted skin swaps the body onto '<material>.skin.<skin>': the mesh file still calls it '<material>'
          local l = { name = nm, mat = mat, layer = layer, mapTo = mapTo:match('^(.-)%.skin%.') or mapTo,
                      base = base == '', pal = (pal == '' and inst) or pal:lower():find('nullcolormaskr', 1, true) ~= nil }
          if l.base or l.pal then out[#out + 1] = l end
        end
      end
    end
  end
  return out
end

local FIELDS = { 'baseColorMap', 'diffuseMapUseUV', 'colorPaletteMap', 'colorPaletteMapUseUV', 'paletteBaseColor', 'emissiveMap', 'emissiveMapUseUV', 'emissiveFactor', 'emissiveIntensityNits' }
local function bind(l)
  local b = bound[l.name] or {}
  if b[l.layer] then return end
  local orig = {}
  for _, f in ipairs(FIELDS) do orig[f] = field(l.mat, f, l.layer) end
  if l.base then
    l.mat:setField('baseColorMap', l.layer, TAG_B)
    l.mat:setField('diffuseMapUseUV', l.layer, '1')      -- the second UV set: the one carSurfaceFx_meshuv maps nodes into
  end
  if l.pal then
    l.mat:setField('colorPaletteMap', l.layer, TAG_P)
    l.mat:setField('colorPaletteMapUseUV', l.layer, '1')
    l.mat:setField('paletteBaseColor', l.layer, '1')
  end
  if litOn() and orig.emissiveMap == '' then                  -- a paint with its own emissive map keeps it
    l.mat:setField('emissiveMap', l.layer, TAG_E)
    l.mat:setField('emissiveMapUseUV', l.layer, '1')
    l.mat:setField('emissiveFactor', l.layer, '1 1 1')
    l.mat:setField('emissiveIntensityNits', l.layer, tostring(settings.dirtGlowNits))
    b.glow = true
  end
  b[l.layer] = orig; bound[l.name] = b
  if l.pal then b.pal = true end
  l.mat:reload()
end

local function hasCanvas(veh)
  for _, t in ipairs(veh:getActiveUITextureTagNames() or {}) do if t == TAG_B then return true end end
  return false
end
-- any car wearing a material we've re-pointed MUST have the two canvases (a missing one renders as garbage)
local function ensureCanvases()
  if not next(bound) then return end
  for _, veh in ipairs(getAllVehicles()) do
    if not hasCanvas(veh) then
      local any, pal, glow = false, false, false
      for _, nm in ipairs(veh:getMaterialNames() or {}) do
        if bound[nm] then any = true; pal = pal or bound[nm].pal glow = glow or bound[nm].glow end
      end
      if any then
        -- no palette to punch through on this car = marks can only darken the paint: tell the page to draw them dark
        veh:createUITexture(TAG_B, PAGE .. (pal and '?m=b' or '?m=b&dark=1') .. '&v=' .. PAGE_V, SIZE, SIZE, UI_TEXTURE_USAGE_AUTOMATIC, FPS)
        veh:createUITexture(TAG_P, PAGE .. '?m=p&v=' .. PAGE_V, SIZE, SIZE, UI_TEXTURE_USAGE_AUTOMATIC, FPS)
        if glow then veh:createUITexture(TAG_E, PAGE .. '?m=e&v=' .. PAGE_V, SIZE, SIZE, UI_TEXTURE_USAGE_AUTOMATIC, FPS) end
      end
    end
  end
end

-- whether every paint material already bound carries the lit page (true when none is bound yet): panel damage asks for a re-bind when it does not
function M.litReady()
  for _, b in pairs(bound) do if not b.glow then return false end end
  return true
end

-- for the panel damage probe: what paint canvases car id has: has a palette to punch (false: marks can only darken), has the lit page (the dirt glow setting)
function M.paintInfo(id)
  local veh = getObjectByID(id)
  if not veh then return nil end
  local pal, glow, any = false, false, false
  for _, nm in ipairs(veh:getMaterialNames() or {}) do
    if bound[nm] then any = true pal = pal or bound[nm].pal == true glow = glow or bound[nm].glow == true end
  end
  return { bound = any, palette = pal, lit = glow, canvas = hasCanvas(veh) }
end

-- put every material back exactly as it was and drop the canvases (each item on its own: one that throws, or a car that is already gone, does not stop the rest)
local function restoreAll()
  for name, layers in pairs(bound) do
    pcall(function()
      local mat = scenetree.findObject(name)
      if mat then
        for layer, orig in pairs(layers) do
          if type(orig) == 'table' then for _, f in ipairs(FIELDS) do mat:setField(f, layer, orig[f]) end end
        end
        mat:reload()
      end
    end)
  end
  bound = {}; cars = {}
  local okV, vehs = pcall(getAllVehicles)
  for _, veh in ipairs(okV and vehs or {}) do
    pcall(function() if hasCanvas(veh) then veh:destroyUITexture(TAG_B); veh:destroyUITexture(TAG_P); pcall(function() veh:destroyUITexture(TAG_E) end) end end)
  end
end

-- the level is ending: its materials and the cars' canvases go with it, so nothing is reloaded or destroyed in the same tick the engine takes the cars down; only our references are dropped
local outq, outHead = {}, 1                                      -- the calls for the paint pages, sent a few a frame (see send)
local function dropAll() bound = {}; cars = {}; outq, outHead = {}, 1 end

-- ---- per-car setup ----
local bodydirt = require('carSurfaceFx/bodydirt')
local function start(veh)
  local id = veh:getId()
  local layers = paintLayers(veh)
  local vd = core_vehicle_manager.getVehicleData(id)
  if #layers == 0 or not vd or not vd.vdata then cars[id] = { none = 'no paint layer we can draw on' }; return end
  local paintMat = {}
  for _, l in ipairs(layers) do paintMat[l.mapTo] = true end
  local mine = { building = true }
  cars[id] = mine
  carSurfaceFx_meshuv.request(id, paintMat, function(lut)
    if cars[id] ~= mine or not getObjectByID(id) then return end   -- car went away or was replaced meanwhile (ids get reused)
    if not lut or lut.count == 0 then cars[id] = { none = 'no source mesh (.dae) with paint UVs found' }; return end
    local d = vd.vdata
    local pos = {}
    for _, n in pairs(d.nodes) do pos[n.cid] = n.pos end
    -- the car's own left/back/up directions at rest, from its reference nodes: the car side reports a
    -- scrape direction as components along these same three node-to-node lines
    local r, axes = d.refNodes and d.refNodes[0], nil
    if r and pos[r.ref] and pos[r.left] and pos[r.back] and pos[r.up] then
      axes = { (pos[r.left] - pos[r.ref]):normalized(), (pos[r.back] - pos[r.ref]):normalized(), (pos[r.up] - pos[r.ref]):normalized() }
    end
    local car = { lut = lut.nodes, count = lut.count, pos = pos, axes = axes, wheels = d.wheels, wheelPts = {} }
    cars[id] = car
    bodydirt.request(id, paintMat, function(map) car.map = map end)       -- where each kind of dirt lands on this car (carSurfaceFx/bodymap.lua)
    for _, l in ipairs(layers) do if lut.mats[l.mapTo] then bind(l) end end
    ensureCanvases()
    nodesAt[id] = os.clock() + 2                              -- the page gets the car's body-node map for the running drops once it is up
    if memory[id] then replayAt[id] = os.clock() + 2 end       -- a rebuilt car gets its marks drawn again once its pages are up
  end)
end

-- Everything for the two paint pages goes through one queue, ONE call per page frame. A web texture runs one queued script per frame of its own (FPS, 10 a second) and the
-- others of that frame are lost: what showed in the game was always about one piece of 40 splats however many were sent (35 in a frame: 30 marks; 120 in a frame: none;
-- 6 a frame: 30 marks).
local SEND_EVERY = 1.3 / FPS
local sendT = 0
local function send(veh, js) outq[#outq + 1] = { veh:getId(), js } end
local function flush(dt)
  sendT = sendT + (dt or 0)
  if sendT < SEND_EVERY then return end
  while outHead <= #outq do
    local e = outq[outHead]
    outq[outHead] = false
    outHead = outHead + 1
    local veh = getObjectByID(e[1])
    local ok, has = pcall(function() return veh and hasCanvas(veh) end)
    if ok and has then veh:queueJSUITexture(TAG_B, e[2]); veh:queueJSUITexture(TAG_P, e[2]); if litOn() then pcall(function() veh:queueJSUITexture(TAG_E, e[2]) end) end sendT = 0 break end
  end
  if outHead > #outq then outq, outHead = {}, 1 end
end

local function draw(veh, fn, data)
  send(veh, fn .. '(' .. jsonEncode(data) .. ')')
end

-- ---- called by carSurfaceFx/bodywear.lua, from the car's contacts ----
-- a body node slid hard against something. a,b,c = the slip direction along the car's left/back/up lines.
function M.hit(id, cid, force, slip, a, b, c)
  local car = cars[id]
  local e = car and car.lut and car.lut[cid]
  if not e or not settings.enabled then return end
  local veh = getObjectByID(id)
  if not veh then return end
  -- slip direction -> direction across the texture (per metre travelled along the panel)
  local du, dv = 0, 0
  if car.axes then
    local d = car.axes[1] * a + car.axes[2] * b + car.axes[3] * c
    local l = d:length()
    if l > 1e-6 then
      du = (e[3] * d.x + e[4] * d.y + e[5] * d.z) / l
      dv = (e[6] * d.x + e[7] * d.y + e[8] * d.z) / l
    end
  end
  local s = e[9]                                             -- texture units per metre here
  local len = (0.06 + min(slip, 15) * 0.02) * settings.markSize   -- metres: faster drag = longer mark
  if du * du + dv * dv < s * s * 0.04 then                    -- hit straight INTO the panel: a short scuff, any direction
    local ang = random() * 6.2832
    du, dv, len = math.cos(ang) * s, math.sin(ang) * s, len * 0.4
  end
  local dl = sqrt(du * du + dv * dv)
  local pu, pv = -dv / dl * s, du / dl * s                    -- one metre sideways
  local sev = min(1, force / 12000)
  local lines = {}
  for i = 1, 2 + floor(sev * 3 + random()) do
    local off, along, half = (random() - 0.5) * 0.035, (random() - 0.5) * len * 0.5, len * (0.3 + random() * 0.7) * 0.5
    local cu, cv = e[1] + pu * off + du * along, e[2] + pv * off + dv * along
    local n = #lines
    lines[n+1], lines[n+2], lines[n+3], lines[n+4] = cu - du * half, 1 - (cv - dv * half), cu + du * half, 1 - (cv + dv * half)
    lines[n+5] = (0.001 + random() * 0.003) * s              -- 1-4mm wide
  end
  draw(veh, 'csfxLines', { l = lines, c = settings.colour, a = settings.opacity * (0.55 + 0.45 * sev) })
  local m = mem(id)
  for i = 1, #lines, 5 do remember(m.marks, { q(lines[i]), q(lines[i + 1]), q(lines[i + 2]), q(lines[i + 3]), q(lines[i + 4], 100000) }) end
end

-- dirt splats on the bodywork around the wheels of car id: n splats of colour c (rgb 0..1) and opacity a, around random wheels. carSurfaceFx calls this from its wheel
-- reports while the wheels run on loose ground, more of it the dirtier the ground.
function M.splat(id, c, a, n, kind)
  local car = cars[id]
  if car and car.map and M.dirtAt(id, kind == 'dust' and 'dust' or 'mud', n * 2, nil, c, a, settings.dirtSize * 0.4) then return end       -- the spray of the wheels lands where it really lands
  if not car or not car.lut or not settings.dirtEnabled or not car.wheels then return end
  local keys = {}
  for wi in pairs(car.wheels) do keys[#keys + 1] = wi end
  if #keys == 0 then return end
  for _ = 1, n do M.wheelDirt(id, keys[random(#keys)], c, a, kind) end
end

-- wheel wi is rolling on loose ground: one dirt splat somewhere on the bodywork around that wheel
function M.wheelDirt(id, wi, colour, opacity, kind)
  local car = cars[id]
  if not car or not car.lut or not settings.dirtEnabled then return end
  local pts = car.wheelPts[wi]
  if not pts then                                            -- the paint nodes within reach of this wheel, worked out once
    pts = {}
    local w = car.wheels and car.wheels[wi]
    local p1, p2 = w and car.pos[w.node1], w and car.pos[w.node2]
    if p1 and p2 then
      local c = (p1 + p2) * 0.5
      for cid in pairs(car.lut) do
        local p = car.pos[cid]
        if p and p.z > c.z - 0.25 and (p - c):length() < 0.95 then pts[#pts + 1] = cid end
      end
    end
    car.wheelPts[wi] = pts
  end
  if #pts == 0 then return end
  local veh = getObjectByID(id)
  if not veh then return end
  local e = car.lut[pts[random(#pts)]]
  local s, blobs = e[9], {}
  for i = 1, 4 do
    local n = #blobs
    blobs[n+1] = e[1] + (random() - 0.5) * 0.2 * s
    blobs[n+2] = 1 - (e[2] + (random() - 0.5) * 0.2 * s)
    blobs[n+3] = settings.dirtSize * (0.4 + random() * 0.6) * s
  end
  draw(veh, 'csfxBlobs', { l = blobs, c = colour or settings.dirtColour, a = opacity or settings.dirtOpacity, k = kind or 'mud' })
  local m = mem(id)
  for i = 1, #blobs, 3 do remember(m.splats, { q(blobs[i]), q(blobs[i + 1]), q(blobs[i + 2], 10000), q(opacity or settings.dirtOpacity), kind == 'dust' and 1 or 2 }) end
end

-- n soft splats on the bodywork where the region says: 'top' (the upper quarter of the body, snow on the roof and hood), 'front' (the front quarter, bugs on the nose),
-- 'lowL' / 'lowR' (the lower third on the left / right side, splash from the wheels; jbeam x is left).
-- Node axes are the jbeam ones (x left, y back, z up). kind 'dust' washes with the dust factor, anything else with the mud factor. size is a multiplier of the splat radius.
function M.bodySplat(id, region, colour, opacity, n, kind, size)
  local car = cars[id]
  if not car or not car.lut or not settings.dirtEnabled then return end
  local veh = getObjectByID(id)
  if not veh then return end
  local pts = car.regions and car.regions[region]
  if not pts then
    local lo, hi, ylo, yhi, xlo, xhi = 1e9, -1e9, 1e9, -1e9, 1e9, -1e9
    for cid in pairs(car.lut) do
      local p = car.pos[cid]
      if p then lo, hi, ylo, yhi, xlo, xhi = min(lo, p.z), max(hi, p.z), min(ylo, p.y), max(yhi, p.y), min(xlo, p.x), max(xhi, p.x) end
    end
    local xm = (xlo + xhi) * 0.5
    pts = {}
    for cid in pairs(car.lut) do
      local p = car.pos[cid]
      if p and ((region == 'top' and p.z > hi - (hi - lo) * 0.25) or (region == 'front' and p.y < ylo + (yhi - ylo) * 0.25)
          or (region == 'lowL' and p.z < lo + (hi - lo) * 0.3 and p.x > xm) or (region == 'lowR' and p.z < lo + (hi - lo) * 0.3 and p.x < xm)) then pts[#pts + 1] = cid end
    end
    car.regions = car.regions or {}
    car.regions[region] = pts
  end
  if #pts == 0 then return end
  local m = mem(id)
  for _ = 1, n do
    local e = car.lut[pts[random(#pts)]]
    local s, blobs = e[9], {}
    for i = 1, 3 do
      local k = #blobs
      blobs[k+1] = e[1] + (random() - 0.5) * 0.25 * s
      blobs[k+2] = 1 - (e[2] + (random() - 0.5) * 0.25 * s)
      blobs[k+3] = settings.dirtSize * (size or 1) * (0.5 + random() * 0.6) * s
    end
    draw(veh, 'csfxBlobs', { l = blobs, c = colour, a = opacity, k = kind or 'mud' })
    for i = 1, #blobs, 3 do remember(m.splats, { q(blobs[i]), q(blobs[i + 1]), q(blobs[i + 2], 10000), q(opacity), kind == 'dust' and 1 or 2 }) end
  end
end

-- Dirt of a kind put where it really lands on this car's body (carSurfaceFx/bodymap.lua): n splats of the colour c (rgb 0..1) and opacity a. kind: 'mud' | 'grime' | 'dust' | 'rubber' |
-- 'snow' | 'bugs' (the rule that picks the places); wi: the wheel that throws it (mud, rubber), nil for any; size in metres (radius); 'soft' kinds wash like dust, the rest like mud.
-- Returns true when the car's body map was used, false when it is not built (the caller falls back to the plain placement).
local SOFT = { dust = true, snow = true, grime = true, snowdust = true }
-- splats to the pages in pieces of 100, with short numbers: one call of 550 splats with 17-digit floats was a 50 kB piece of script, more than a web texture may take
local function drawSplats(veh, list, dirs, props)
  for first = 1, #list, 300 do
    local l, d = {}, {}
    for i = first, math.min(#list, first + 299), 3 do
      l[#l + 1], l[#l + 2], l[#l + 3] = q(list[i], 10000), q(list[i + 1], 10000), q(list[i + 2], 100000)
      if dirs then local j = (i - 1) / 3 * 2 + 1 d[#d + 1], d[#d + 2] = q(dirs[j], 1000), q(dirs[j + 1], 1000) end
    end
    draw(veh, 'csfxBlobs', { l = l, d = dirs and d or nil, c = props.c, a = props.a, k = props.k, t = props.t })
  end
end
function M.useLut(id, lut) cars[id] = { lut = lut } end                                       -- (for the tests: a car's node map without the mesh reading)
function M.useMap(id, map) cars[id] = cars[id] or {} cars[id].map = map end                    -- (for the tests: a car's body map without the mesh reading)
local dd = { calls = 0, refused = 0, sent = 0, clods = 0, last = 'never' }              -- what dirtAt did, for diagnose()
function M.dirtAt(id, kind, n, wi, c, a, size, opts)
  local car = cars[id]
  local map = car and car.map
  local veh = getObjectByID(id)
  dd.calls = dd.calls + 1
  if not (map and veh and settings.dirtEnabled) then dd.refused = dd.refused + 1 dd.last = string.format('%s refused (car %s, map %s, veh %s, dirtEnabled %s)', kind, tostring(car ~= nil), tostring(map ~= nil), tostring(veh ~= nil), tostring(settings.dirtEnabled)) return false end
  local list
  if wi == nil and (kind == 'mud' or kind == 'rubber') and #map.wheels > 1 then                  -- every wheel throws its share (one wheel for the whole call put it all on one corner)
    list = {}
    local per = math.max(1, math.floor(n / #map.wheels + 0.5))
    for w = 1, #map.wheels do for _, s in ipairs(bodymap.sample(map, kind, per, random, w, opts and opts.maxH and opts or nil)) do list[#list + 1] = s; wi = w end end
  else
    if wi == nil and (kind == 'mud' or kind == 'rubber') and #map.wheels > 0 then wi = random(#map.wheels) end
    list = bodymap.sample(map, kind, n, random, wi, opts and opts.maxH and opts or nil)
  end
  if #list == 0 then return true end
  local blobs, dirs, cakes = {}, {}, {}
  for i, s in ipairs(list) do
    local h = s.h or (s.z and bodymap.heightOf(map, s.z))                            -- how high on the car (0 sill .. 1 roof)
    if kind == 'mud' and h and h < 0.35 and random() < 0.5 then                       -- the lowest dirt is thick: a clod, bigger than a splat, in its own layer
      cakes[#cakes + 1], cakes[#cakes + 2], cakes[#cakes + 3] = s.u, canvasV(s.v), size * (1.0 + 1.4 * random() ^ 1.5) * s.s
    else
      local k = #blobs
      blobs[k + 1], blobs[k + 2], blobs[k + 3] = s.u, canvasV(s.v), size * (kind == 'mud' and (0.3 + 0.9 * random() ^ 2) or (0.6 + 0.8 * random())) * s.s       -- mud: many small, a few big; the soft kinds: even patches
      if s.dx then dirs[#dirs + 1], dirs[#dirs + 2] = s.dx, -s.dy else dirs[#dirs + 1], dirs[#dirs + 2] = 0, 0 end   -- the canvas has y turned over
    end
  end
  local soft = SOFT[kind] and 'dust' or 'mud'
  local m = mem(id)
  dd.sent, dd.clods, dd.last = dd.sent + #blobs / 3, dd.clods + #cakes / 3, string.format('%s: %d splats, %d clods, wheel %s', kind, #blobs / 3, #cakes / 3, tostring(wi))
  if #blobs > 0 then
    drawSplats(veh, blobs, dirs, { c = c, a = a, k = soft, t = (opts and opts.tex) or (kind == 'snowdust' and 'snow') or kind })
    for i = 1, #blobs, 3 do remember(m.splats, { q(blobs[i]), q(blobs[i + 1]), q(blobs[i + 2], 10000), q(a), soft == 'dust' and 1 or 2 }) end
  end
  if #cakes > 0 then
    drawSplats(veh, cakes, nil, { c = c, a = math.min(1, a + 0.1), k = 'cake', t = (opts and opts.tex) or 'mud' })
    for i = 1, #cakes, 3 do remember(m.splats, { q(cakes[i]), q(cakes[i + 1]), q(cakes[i + 2], 10000), q(a), 2 }) end
  end
  return true
end

-- ---- steady paint wear (carSurfaceFx.setPaintWear, docs/PAINT_WEAR.md): fade, grime, scuffs and rust 0..1 on the car's paint, drawn by the page as a layer under the dirt.
-- The places are picked once per car (seeded by the car's id, so a respawn gives the same ones) from the body map and sent with the values; the page uses more of them as a value grows.
local wears, wearPos, wearDue = {}, {}, {}                  -- id -> values | id -> places | id -> when to send
local WEAR_KEYS = { 'fade', 'grime', 'scuffs', 'rust' }
local function wearPlaces(id)
  if wearPos[id] then return wearPos[id] end
  local car = cars[id]
  local map = car and car.map
  if not map then return nil end
  local seed = id * 7919 + 17
  local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
  local function pick(kind, n, radius)
    local out = {}
    for _, s in ipairs(bodymap.sample(map, kind, n, rnd)) do
      out[#out + 1], out[#out + 2], out[#out + 3] = q(s.u, 10000), q(canvasV(s.v), 10000), q(radius * (0.6 + 0.8 * rnd()) * s.s, 100000)
    end
    return out
  end
  -- rust: a list of x, y, radius, run-off direction (x, y); two thirds small spots first (the page uses the first part of a list, so a little rust is many small spots), then bigger ones
  local rl = {}
  local rs = bodymap.sample(map, 'rust', 260, rnd)
  for i, s in ipairs(rs) do
    local r = (i <= 170 and 0.016 or 0.04) * (0.6 + 0.8 * rnd()) * s.s
    rl[#rl + 1], rl[#rl + 2], rl[#rl + 3], rl[#rl + 4], rl[#rl + 5] = q(s.u, 10000), q(canvasV(s.v), 10000), q(r, 100000), q(s.dx or 0, 100), q(-(s.dy or 0), 100)       -- (the canvas has y turned over)
  end
  wearPos[id] = { fl = pick('wear', 120, 0.4), gl = pick('wearlow', 120, 0.3), sl = pick('wear', 120, 0.25), rl = rl }       -- the road film gathers low on the body
  return wearPos[id]
end
-- w = { fade=, grime=, scuffs=, rust= } each 0..1; nil or all zeros takes the layer away
function M.setPaintWear(id, w)
  if not getObjectByID(id) then wears[id] = nil wearDue[id] = nil return end
  local new, any, same = {}, false, true
  for _, k in ipairs(WEAR_KEYS) do
    new[k] = q(min(1, max(0, tonumber(w and w[k]) or 0)), 100)
    any = any or new[k] > 0
    if math.abs(new[k] - (wears[id] and wears[id][k] or 0)) >= 0.02 then same = false end
  end
  if same and (any or not wears[id]) then return end       -- unchanged (or still none): nothing to send
  wears[id] = any and new or nil
  wearDue[id] = os.clock()
end
local function sendWear(id)
  local car, veh, w = cars[id], getObjectByID(id), wears[id]
  if not (veh and hasCanvas(veh)) then return false end
  if not w then draw(veh, 'csfxWear', {}) return true end
  local p = wearPlaces(id)
  if not p then return false end             -- the body map is not ready yet
  draw(veh, 'csfxWear', { fade = w.fade, grime = w.grime, scuffs = w.scuffs, rust = w.rust, fl = p.fl, gl = p.gl, sl = p.sl, rl = p.rl })
  return true
end
function M.paintWear(id) return wears[id] end

-- carSurfaceFx_scratch.glowTune(nits): the brightness of the lit dirt colour on the cars already bound (a test: how strong it must be to read as the dirt's own colour by day)
function M.glowTune(nits)
  nits = tonumber(nits) or DEFAULT_GLOW_NITS                     -- no argument: back to the default
  settings.dirtGlowNits = nits
  local n = 0
  for name, layers in pairs(bound) do
    local mat = scenetree.findObject(name)
    if mat and layers.glow then
      for layer, orig in pairs(layers) do if type(orig) == 'table' and orig.emissiveMap == '' then mat:setField('emissiveIntensityNits', layer, tostring(nits)) n = n + 1 end end
      mat:reload()
    end
  end
  return 'lit dirt ' .. nits .. ' nits on ' .. n .. ' paint layers'
end

-- the car's paint lightness 0..1 (the lit dirt page makes mud stronger on a dark paint); sent when it changed
local lumSent = {}
function M.setPaintLum(id, lum)
  if lumSent[id] and math.abs(lumSent[id] - lum) < 0.04 then return end
  lumSent[id] = lum
  local veh = getObjectByID(id)
  if veh then send(veh, ('csfxPaintLum(%.3f)'):format(lum)) end
end

-- washing: every splat's opacity times fDust / fMud (0..1) on car id (every car with canvases when id is nil). The scratches are not touched.
local slides = 0                                       -- melt washes sent to the pages (for snowStatus)
function M.slideCount() return slides end
function M.washSplats(id, fDust, fMud, slide)
  if slide then slides = slides + 1 end
  for _, veh in ipairs(getAllVehicles()) do
    if (id == nil or veh:getId() == id) and hasCanvas(veh) then
      send(veh, ('csfxWash({dust:%.4f,mud:%.4f%s})'):format(fDust, fMud, slide and ',slide:1' or ''))
    end
  end
  for vid, m in pairs(memory) do
    if id == nil or vid == id then
      local keep = {}
      for _, sp in ipairs(m.splats) do
        sp[4] = q(sp[4] * (sp[5] == 1 and fDust or fMud))
        if sp[4] > 0.04 then keep[#keep + 1] = sp end
      end
      m.splats = keep
    end
  end
end

-- panel damage on a car nobody drives (a parked car that is hit): start its paint map on demand. Returns true when the map is ready now (the first call returns false while the mesh is read)
function M.ensureCar(id)
  local veh = getObjectByID(id)
  if veh and not cars[id] and active() then start(veh) end
  return M.hasMap(id)
end
function M.hasMap(id) local c = cars[id] return c ~= nil and c.lut ~= nil end

-- repair: the scratches of car id buffed out (every car's when id is nil); the dirt stays
function M.repair(id)
  for _, veh in ipairs(getAllVehicles()) do
    if (id == nil or veh:getId() == id) and hasCanvas(veh) then send(veh, 'csfxRepair()') end
  end
  for vid, m in pairs(memory) do if id == nil or vid == id then m.marks = {} m.dents = {} end end      -- (a repaired car has no dents either)
end

function M.buffOut()
  memory = {}
  for _, veh in ipairs(getAllVehicles()) do
    if hasCanvas(veh) then send(veh, 'csfxClear()') end
  end
end

-- ---- panel damage (carSurfaceFx/paneldamage.lua, docs/PANEL_DAMAGE.md): a dent on the paint at a node, drawn as a shaded and a lit half on the paint canvases.
-- rM: the radius in metres, sev 0..1 (the depth), maxMarks: the most dents kept per car (the oldest go). Returns true when it was drawn (false: the car has no map or no canvases).
local LIGHT_DIR_FALLBACK = 2.35                                   -- radians, when the light runs straight into the panel
local KIND_CODE = { plastic = 1, fibreglass = 2, carbon = 3, metal = 4 }
local KIND_LETTER = { 'p', 'f', 'c', 'm' }
-- spreadM (optional): scatter the mark up to that many metres around the node, for the extra marks of a hard hit
-- A node the paint map does not know (a part the paint layer does not paint: a bumper cover, a mirror housing) takes the entry of the nearest mapped node, at most 0.7 m away, so the mark
-- shows on the painted panel beside the part that was hit. The mapped nodes' positions are listed once per car; the answer per node is kept.
local function nearEntry(car, veh, cid)
  car.near = car.near or {}
  local hit = car.near[cid]
  if hit ~= nil then return hit or nil end
  local rules = require('carSurfaceFx/panelrules')
  if not car.points then
    car.points = {}
    for c in pairs(car.lut) do
      local ok, p = pcall(function() return veh:getNodePosition(c) end)
      if ok and p then car.points[#car.points + 1] = { p.x, p.y, p.z, c } end
    end
  end
  local ok, p = pcall(function() return veh:getNodePosition(cid) end)
  local best = ok and p and rules.nearestPoint(car.points, p.x, p.y, p.z, rules.NEAR_M)
  car.near[cid] = best and car.lut[best] or false
  return best and car.lut[best] or nil
end

function M.dent(id, cid, sev, rM, maxMarks, light, kind, spreadM)
  local car = cars[id]
  local veh = getObjectByID(id)
  local e = car and car.lut and car.lut[cid]
  if car and car.lut and not e and veh then e = nearEntry(car, veh, cid) end
  if not e then return false end
  if not veh or not hasCanvas(veh) then return false end
  -- the light in the car's own left / back / up components, turned into a direction across the texture here (as the scratch hit does for a slip direction)
  local ang = LIGHT_DIR_FALLBACK
  if car.axes and light then
    local d = car.axes[1] * light[1] + car.axes[2] * light[2] + car.axes[3] * light[3]
    local du = e[3] * d.x + e[4] * d.y + e[5] * d.z
    local dv = e[6] * d.x + e[7] * d.y + e[8] * d.z
    if du * du + dv * dv > 1e-6 * e[9] * e[9] then ang = math.atan2(-dv, du) end      -- (the canvas runs down: y = 1 - v)
  end
  local r = max(0.004, min(0.2, rM * e[9]))
  local ox, oy = 0, 0
  if spreadM and spreadM > 0 then
    local a, d = math.random() * 6.2832, spreadM * e[9] * math.sqrt(math.random())      -- (texture units: e[9] is per metre)
    ox, oy = math.cos(a) * d, math.sin(a) * d
  end
  local rec = { q(max(0, min(1, e[1] + ox))), q(max(0, min(1, 1 - e[2] + oy))), q(r, 10000), q(ang, 100), q(sev, 100), KIND_CODE[kind] or 4 }
  draw(veh, 'csfxDent', { x = rec[1], y = rec[2], r = rec[3], ang = rec[4], d = rec[5], k = KIND_LETTER[rec[6]] })
  local m = mem(id)
  m.dents = m.dents or {}
  m.dents[#m.dents + 1] = rec
  while #m.dents > (maxMarks or 40) do table.remove(m.dents, 1) end
  return true
end

-- the node of car id (one the map knows) nearest to a world position, and how far it is, or nil
function M.nearestNode(id, worldPos, maxDist)
  local car, veh = cars[id], getObjectByID(id)
  if not (car and car.lut and veh and worldPos) then return nil end
  local best, bd = nil, (maxDist or 0.4) ^ 2
  local origin = veh:getPosition()
  for cid in pairs(car.lut) do
    local ok, rel = pcall(function() return veh:getNodePosition(cid) end)
    if ok and rel then
      local dx, dy, dz = origin.x + rel.x - worldPos.x, origin.y + rel.y - worldPos.y, origin.z + rel.z - worldPos.z
      local d2 = dx * dx + dy * dy + dz * dz
      if d2 < bd then best, bd = cid, d2 end
    end
  end
  return best, best and math.sqrt(bd) or nil
end

-- the node ids (cid) of car id that the paint map knows, in no particular order (for the probe)
function M.mappedNodes(id)
  local car, out = cars[id], {}
  if car and car.lut then for cid in pairs(car.lut) do out[#out + 1] = cid end table.sort(out) end
  return out
end

-- how many dents car id carries
function M.dentCount(id) local m = memory[id] return m and m.dents and #m.dents or 0 end

-- how many scratches car id carries (the last MEMORY_CAP are remembered)
function M.count(id) local m = memory[id] return m and #m.marks or 0 end

-- the marks of car id as plain numbers (the last 40 scratch lines and splats), or nil
function M.getState(id)
  local m = memory[id]
  if not m or (#m.marks == 0 and #m.splats == 0 and #(m.dents or {}) == 0) then return nil end
  local out = { marks = {}, splats = {} }
  if m.dents and #m.dents > 0 then out.dents = {} for _, r in ipairs(m.dents) do out.dents[#out.dents + 1] = { unpack(r) } end end
  for i = math.max(1, #m.marks - 39), #m.marks do out.marks[#out.marks + 1] = { unpack(m.marks[i]) } end
  for i = math.max(1, #m.splats - 39), #m.splats do out.splats[#out.splats + 1] = { unpack(m.splats[i]) } end
  return out
end

-- put marks back on car id (from getState): remembered now, drawn as soon as the car's canvases are up
function M.restore(id, st)
  local m = { marks = {}, splats = {}, dents = {} }
  for _, r in ipairs(type(st) == 'table' and st.dents or {}) do if #r >= 5 then m.dents[#m.dents + 1] = { r[1], r[2], r[3], r[4], r[5], r[6] or 4 } end end
  for _, r in ipairs(type(st) == 'table' and st.marks or {}) do if #r >= 5 then m.marks[#m.marks + 1] = { r[1], r[2], r[3], r[4], r[5] } end end
  for _, r in ipairs(type(st) == 'table' and st.splats or {}) do if #r >= 5 then m.splats[#m.splats + 1] = { r[1], r[2], r[3], r[4], r[5] } end end
  memory[id] = m
  replayAt[id] = os.clock() + 1
  restoredAt[id] = os.clock()
end

local function replay(id)
  local m, veh = memory[id], getObjectByID(id)
  if not m or not veh then return end
  for i = 1, #m.marks, 10 do
    local l = {}
    for j = i, math.min(i + 9, #m.marks) do for k = 1, 5 do l[#l + 1] = m.marks[j][k] end end
    draw(veh, 'csfxLines', { l = l, c = settings.colour, a = settings.opacity * 0.8 })
  end
  for _, dn in ipairs(m.dents or {}) do draw(veh, 'csfxDent', { x = dn[1], y = dn[2], r = dn[3], ang = dn[4], d = dn[5], k = KIND_LETTER[dn[6] or 4] }) end
  for _, sp in ipairs(m.splats) do
    draw(veh, 'csfxBlobs', { l = { sp[1], sp[2], sp[3] }, c = sp[5] == 1 and DUST or MUD, a = sp[4], k = sp[5] == 1 and 'dust' or 'mud' })
  end
end

-- the body-node map for the running rain drops: per node its place on the texture (x, y as the marks use them), how a direction in the car's coordinates moves it, and the
-- texture units per metre there (see paintwater.js)
local function sendNodes(id)
  local car, veh = cars[id], getObjectByID(id)
  if not (car and car.lut and veh) then return 0 end
  local rows, calls = {}, 0
  local function flush(more)
    veh:queueJSUITexture(TAG_B, 'csfxNodes(' .. jsonEncode(rows) .. (more and ',1' or ',0') .. ')')
    rows, calls = {}, calls + 1
  end
  local n = 0
  for _, e in pairs(car.lut) do
    rows[#rows + 1] = q(e[1], 10000); rows[#rows + 1] = q(1 - e[2], 10000)
    rows[#rows + 1] = q(e[3], 1000); rows[#rows + 1] = q(e[4], 1000); rows[#rows + 1] = q(e[5], 1000)
    rows[#rows + 1] = q(-e[6], 1000); rows[#rows + 1] = q(-e[7], 1000); rows[#rows + 1] = q(-e[8], 1000)
    rows[#rows + 1] = q(e[9], 10000)
    n = n + 1
    if n % 60 == 0 then flush(calls > 0) end                      -- pieces of 60 nodes; every piece after the first adds to the map
  end
  if #rows > 0 then flush(calls > 0) end
  return calls
end

-- carSurfaceFx_scratch.water(id, { rain, wet, speed, aLong, aLat }): the weather and the car's motion for the drops on the paint. The force on the water in the car's own
-- coordinates (along its left / back / up lines): gravity, the car's acceleration thrown back at the water, and the wind of driving along the body.
local waterCalls, waterSent, lastWaterJs, waterWhy = 0, 0, '', ''
function M.water(id, p)
  waterCalls = waterCalls + 1
  local car, veh = cars[id], getObjectByID(id)
  if not (settings.water and car and car.lut and veh and hasCanvas(veh)) then
    waterWhy = ('settings.water=%s car=%s lut=%s veh=%s canvas=%s'):format(tostring(settings.water), tostring(car ~= nil), tostring(car and car.lut ~= nil), tostring(veh ~= nil), tostring(veh and hasCanvas(veh)))
    return
  end
  -- a page that is still loading drops what it is sent, and the page cannot tell us it is up: send the node map again every 20 s (it is cheap and replaces the old one)
  if (nodesSent[id] or 0) + 20 < os.clock() then sendNodes(id) nodesSent[id] = os.clock() end
  -- the car's own left / back / up lines when its reference nodes give them, else the jbeam axes (x left, y back, z up: gravity is right either way)
  local ax = car.axes or { vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1) }
  local f = ax[1] * p.aLat + ax[2] * (p.aLong + p.speed * p.speed / 80) + ax[3] * -9.8
  -- a number that is not finite would print as 'nan' or 'inf', which is no JavaScript: the whole call would be lost and the page would never get any rain
  local function ok(v) return (v == v and v > -1e6 and v < 1e6) and v or 0 end
  local fx, fy, fz = ok(f.x), ok(f.y), ok(f.z)
  if fx == 0 and fy == 0 and fz == 0 then fz = -9.8 end
  lastWaterJs = ('csfxWater({rain:%.3f,wet:%.3f,fx:%.3f,fy:%.3f,fz:%.3f,mm:%.2f,amount:%.2f,imp:%.2f,anim:%.2f})'):format(ok(p.rain), ok(p.wet), fx, fy, fz, ok(p.mm or 4.5), ok(p.amount or 1), ok(p.imp or 0), ok(p.anim or 1))
  waterSent = waterSent + 1
  waterWhy = ''                                               -- (a send worked: the old blocked reason is stale)
  veh:queueJSUITexture(TAG_B, lastWaterJs)
end

-- carSurfaceFx_scratch.waterDebug(true): the player car's paint shows its body nodes as small black dots, the running drops as big black discs and the page's numbers as black text (the base map multiplies the paint colour: only dark shows on bright paint) (and sends the node map again)
function M.waterDebug(on)
  local veh = getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  local pieces = sendNodes(veh:getId())
  veh:queueJSUITexture(TAG_B, 'csfxDebug(' .. (on and 1 or 0) .. ')')
  local car = cars[veh:getId()]
  if on then veh:queueJSUITexture(TAG_B, 'csfxWater({rain:1,wet:1,fx:0,fy:0,fz:-9.8})') end
  return 'water debug ' .. tostring(on) .. ', axes ' .. tostring(car and car.axes ~= nil) .. ', node map sent in ' .. tostring(pieces) .. ' pieces, nodes ' .. tostring(car and car.count or 'none') .. ', settings.water ' .. tostring(settings.water)
end

-- carSurfaceFx_scratch.buffOut(): every car's scratches and splats gone
-- console helper: what each spawned car ended up with
function M.status()
  local out = {}
  for _, veh in ipairs(getAllVehicles()) do
    local id = veh:getId()
    local car = cars[id]
    local s = not car and 'not set up (not the player car, or the feature is off)' or car.building and 'reading its mesh...'
      or car.none or ('ready - %d body nodes mapped onto the paint'):format(car.count)
    out[#out + 1] = ('vehicle %d (%s): %s'):format(id, tostring(veh.JBeam), s)
    log('I', logTag, out[#out])
  end
  return table.concat(out, '\n')
end

-- why a car is (not) set up: every material of the player car with what the paint test sees, and the mapper's state
function M.diagnose()
  local veh = getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  local out = { ('settings enabled=%s dirtEnabled=%s allVehicles=%s; mapper busy=%s; canvas=%s'):format(tostring(settings.enabled), tostring(settings.dirtEnabled),
    tostring(settings.allVehicles), tostring(carSurfaceFx_meshuv and carSurfaceFx_meshuv.busy and carSurfaceFx_meshuv.busy()), tostring(hasCanvas(veh))) }
  local car = cars[veh:getId()]
  out[#out + 1] = 'car state: ' .. (not car and 'nil (start() never ran)' or car.building and 'building' or car.none or ('ready, %d nodes'):format(car.count))
  out[#out + 1] = ('paintLayers found: %d'):format(#paintLayers(veh))
  for _, nm in ipairs(veh:getMaterialNames() or {}) do
    local mat = scenetree.findObject(nm)
    if mat then
      local line = ('%s class=%s translucent=%s activeLayers=%s'):format(nm, tostring(mat:getClassName()), field(mat, 'translucent', 0), field(mat, 'activeLayers', 0))
      for layer = 0, 1 do
        line = line .. (' | L%d pal=%s base=%s inst=%s palBase=%s'):format(layer, field(mat, 'colorPaletteMap', layer):match('[^/]*$'), field(mat, 'baseColorMap', layer):match('[^/]*$'),
          field(mat, 'instanceDiffuse', layer), field(mat, 'paletteBaseColor', layer))
      end
      if line:find('pal=[^ ]') and not line:find('pal= ') then out[#out + 1] = line end
    end
  end
  out[#out + 1] = ('paint water: %d calls, %d sent, last [%s], blocked because [%s], map sent %s s ago'):format(waterCalls, waterSent, lastWaterJs, waterWhy, tostring(nodesSent[veh:getId()] and math.floor(os.clock() - nodesSent[veh:getId()]) or 'never'))
  out[#out + 1] = string.format('dirtAt: %d calls, %d refused, %d splats and %d clods sent, last: %s', dd.calls, dd.refused, dd.sent, dd.clods, dd.last)
  out[#out + 1] = 'canvases on the car: ' .. table.concat(veh:getActiveUITextureTagNames() or {}, ', ')
  for nm, layers in pairs(bound) do
    local mat = scenetree.findObject(nm)
    for layer, orig in pairs(layers) do
      if type(orig) == 'table' and mat then
        out[#out + 1] = ('bound %s L%d: now baseColorMap=%s colorPaletteMap=%s paletteBaseColor=%s (was %s / %s)'):format(nm, layer, field(mat, 'baseColorMap', layer), field(mat, 'colorPaletteMap', layer),
          field(mat, 'paletteBaseColor', layer), tostring(orig.baseColorMap), tostring(orig.colorPaletteMap))
      end
    end
  end
  return table.concat(out, '\n')
end

-- carSurfaceFx_scratch.probe(): a big red cross on the player car's canvases; if it never shows on the paint, the page or the binding does not reach the material
-- carSurfaceFx_scratch.stamp(): 36 big red marks, ONE per call, one call per 0.13 s, on a 6 x 6 grid of the paint map: how many of them show on the car says how many calls arrive
-- (each mark is a call of its own; count the red marks)
function M.stamp()
  local veh = getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  for gx = 0, 5 do for gy = 0, 5 do
    draw(veh, 'csfxBlobs', { l = { (gx + 0.5) / 6, (gy + 0.5) / 6, 0.03 }, c = { 1, 0.1, 0.1 }, a = 1, k = 'mud' })
  end end
  return '36 calls queued, one every 0.13 s'
end

function M.probe()
  local veh = getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  send(veh, 'csfxProbe()')
  return 'probe sent; canvases: ' .. table.concat(veh:getActiveUITextureTagNames() or {}, ', ')
end

-- drop a few test scratches + dirt on the player car without needing a crash (console / Debug tab)
function M.test()
  local veh = getPlayerVehicle(0)
  local car = veh and cars[veh:getId()]
  if not car or not car.lut then log('W', logTag, 'player car is not set up yet - see carSurfaceFx_scratch.status()'); return 'player car is not set up yet: ' .. M.status() end
  local ids = tableKeys(car.lut)
  for i = 1, 60 do M.hit(veh:getId(), ids[random(#ids)], 4000 + random() * 12000, 3 + random() * 10, random() - 0.5, random() - 0.5, (random() - 0.5) * 0.4) end
  for wi in pairs(car.wheels or {}) do for i = 1, 6 do M.wheelDirt(veh:getId(), wi) end end
  return '60 scratches and wheel dirt drawn'
end

-- ---- lifecycle ----
function M.onExtensionLoaded() end
local pollTimer = 0
local checkResets                                              -- (defined with onVehicleResetted below)
function M.onUpdate(dt)
  flush(dt)
  carSurfaceFx_meshuv.tick()
  bodydirt.tick()
  checkResets()
  pollTimer = pollTimer + (dt or 0)
  if pollTimer < 1.0 then return end
  pollTimer = 0
  local player = be:getPlayerVehicleID(0)
  for _, veh in ipairs(getAllVehicles()) do
    injectVehicle(veh)                                        -- a reloaded car has a fresh VM: re-inject is cheap + idempotent
    local id = veh:getId()
    if active() and not cars[id] and (settings.allVehicles or id == player) then start(veh) end
  end
  ensureCanvases()
  for id, t in pairs(nodesAt) do
    local car, veh = cars[id], getObjectByID(id)
    if t <= os.clock() and car and car.lut and veh and hasCanvas(veh) then sendNodes(id) nodesAt[id] = nil end
  end
  for id, t in pairs(wearDue) do
    if t <= os.clock() then
      if not getObjectByID(id) then wearDue[id] = nil wears[id] = nil wearPos[id] = nil       -- the car is gone
      elseif sendWear(id) then wearDue[id] = nil
      else wearDue[id] = os.clock() + 1 end                    -- no canvas or body map yet: look again in a second
    end
  end
  for id, t in pairs(replayAt) do
    local car, veh = cars[id], getObjectByID(id)
    if t <= os.clock() and car and car.lut and veh and hasCanvas(veh) then replay(id) replayAt[id] = nil end
  end
end
function M.onVehicleSpawned(id)
  injectedAt[id] = nil
  wearPos[id] = nil if wears[id] then wearDue[id] = os.clock() + 2 end       -- new mesh, new canvases: the wear is drawn again
  cars[id] = nil                                              -- new parts = new mesh; its canvases died with the old car
  ensureCanvases()
end
-- the car was reset or recovered: the marks follow the car's REAL damage. If it is whole again (free roam R, a garage or body shop repair) the scratches and the panel marks go (the
-- dirt stays); a recovery or tow that keeps the physical damage keeps them too. The vehicle reports its damage a moment after the reset, so this looks again 0.7 s later, at
-- map.objects[id].damage (the vehicle's dissipated energy; 0 on a new car). An unknown damage keeps the marks. A restore on a respawned car is left alone for 5 seconds (a spawn can reset once).
local WHOLE = 20
local resetAt = {}
function M.onVehicleResetted(id)
  if restoredAt[id] and os.clock() - restoredAt[id] < 5 then return end
  resetAt[id] = os.clock() + 0.7
end
local function damageOf(id)
  local m = rawget(_G, 'map')
  local o = m and m.objects and m.objects[id]
  return o and tonumber(o.damage) or nil
end
function checkResets()
  for id, t in pairs(resetAt) do
    if t <= os.clock() then
      resetAt[id] = nil
      local dmg = damageOf(id)
      if dmg and dmg < WHOLE then M.repair(id) end
    end
  end
end
function M.onVehicleDestroyed(id) resetAt[id] = nil restoredAt[id] = nil injectedAt[id] = nil cars[id] = nil memory[id] = nil replayAt[id] = nil nodesAt[id] = nil wears[id] = nil wearPos[id] = nil wearDue[id] = nil nodesSent[id] = nil lumSent[id] = nil end
function M.onClientEndMission()   dropAll() end
function M.onExtensionUnloaded()  restoreAll() end

return M
