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
    * WHEN: carSurfaceFxScratch.lua (car side) reports hard sliding body hits and
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
local logTag = 'carSurfaceFx_scratch'
local TAG_B, TAG_P = '@csfx_base', '@csfx_palette'
local PAGE = 'local://local/vehicles/common/carSurfaceFx/scratch.html'
local SIZE, FPS = 1024, 6   -- the engine caps a web texture near the screen size: 2048 came back part garbage

local random, sqrt, floor, min, max = math.random, math.sqrt, math.floor, math.min, math.max

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
    allVehicles = false,                            -- false = just the car you're in (matches Body Dirt)
  }
end
local settings = defaults()

local cars  = {}     -- vehId -> { building=true } | { none=true } | { lut=, pos=, axes=, wheelPts={} }
local bound = {}     -- material name -> { [layer] = original field values }

-- the settings come from carSurfaceFx (settings.scratch): enabled, colour, opacity, markSize, dirtEnabled, dirtColour, dirtOpacity, dirtSize, dirtRate, allVehicles
function M.configure(t)
  settings = defaults()
  for k, v in pairs(t or {}) do if settings[k] ~= nil then settings[k] = v end end
end
local function active() return settings.enabled or settings.dirtEnabled end

-- ---- the car-side reporter ----
local function pushCmd()
  return ('if carSurfaceFxScratch then carSurfaceFxScratch.setConfig(%s) end'):format(tostring(settings.enabled))
end
local function injectVehicle(veh)
  veh:queueLuaCommand("if not carSurfaceFxScratch then extensions.load('carSurfaceFxScratch') end " .. pushCmd())
end

-- ---- materials ----
local function truthy(v) return v == true or v == 1 or v == '1' or v == 'true' end
local function field(mat, name, layer) return tostring(mat:getField(name, layer) or '') end

-- every paint layer on this car we could draw on: { name=, mat=, layer=, mapTo=, base=bool, pal=bool }
local function paintLayers(veh)
  local out = {}
  for _, nm in ipairs(veh:getMaterialNames() or {}) do
    local mat = scenetree.findObject(nm)
    if mat and mat:getClassName() == 'Material' and not truthy(mat:getField('translucent', 0)) then
      for layer = 0, (tonumber(mat.activeLayers) or 1) - 1 do
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

local FIELDS = { 'baseColorMap', 'diffuseMapUseUV', 'colorPaletteMap', 'colorPaletteMapUseUV', 'paletteBaseColor' }
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
      local any, pal = false, false
      for _, nm in ipairs(veh:getMaterialNames() or {}) do
        if bound[nm] then any = true; pal = pal or bound[nm].pal end
      end
      if any then
        -- no palette to punch through on this car = marks can only darken the paint: tell the page to draw them dark
        veh:createUITexture(TAG_B, PAGE .. (pal and '?m=b' or '?m=b&dark=1'), SIZE, SIZE, UI_TEXTURE_USAGE_AUTOMATIC, FPS)
        veh:createUITexture(TAG_P, PAGE .. '?m=p', SIZE, SIZE, UI_TEXTURE_USAGE_AUTOMATIC, FPS)
      end
    end
  end
end

-- put every material back exactly as it was and drop the canvases
local function restoreAll()
  for name, layers in pairs(bound) do
    local mat = scenetree.findObject(name)
    if mat then
      for layer, orig in pairs(layers) do
        if type(orig) == 'table' then for _, f in ipairs(FIELDS) do mat:setField(f, layer, orig[f]) end end
      end
      mat:reload()
    end
  end
  bound = {}; cars = {}
  for _, veh in ipairs(getAllVehicles()) do
    if hasCanvas(veh) then veh:destroyUITexture(TAG_B); veh:destroyUITexture(TAG_P) end
  end
end

-- ---- per-car setup ----
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
    cars[id] = { lut = lut.nodes, count = lut.count, pos = pos, axes = axes, wheels = d.wheels, wheelPts = {} }
    for _, l in ipairs(layers) do if lut.mats[l.mapTo] then bind(l) end end
    ensureCanvases()
  end)
end

local function draw(veh, fn, data)
  local js = fn .. '(' .. jsonEncode(data) .. ')'
  veh:queueJSUITexture(TAG_B, js); veh:queueJSUITexture(TAG_P, js)
end

-- ---- called from the car (carSurfaceFxScratch.lua) ----
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
end

-- dirt splats on the bodywork around the wheels of car id: n splats of colour c (rgb 0..1) and opacity a, around random wheels. carSurfaceFx calls this from its wheel
-- reports while the wheels run on loose ground, more of it the dirtier the ground.
function M.splat(id, c, a, n, kind)
  local car = cars[id]
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
end

-- washing: every splat's opacity times fDust / fMud (0..1) on car id (every car with canvases when id is nil). The scratches are not touched.
function M.washSplats(id, fDust, fMud)
  for _, veh in ipairs(getAllVehicles()) do
    if (id == nil or veh:getId() == id) and hasCanvas(veh) then
      local js = ('csfxWash({dust:%.4f,mud:%.4f})'):format(fDust, fMud)
      veh:queueJSUITexture(TAG_B, js); veh:queueJSUITexture(TAG_P, js)
    end
  end
end

-- repair: every car's scratches buffed out; the dirt stays
function M.repair()
  for _, veh in ipairs(getAllVehicles()) do
    if hasCanvas(veh) then veh:queueJSUITexture(TAG_B, 'csfxRepair()'); veh:queueJSUITexture(TAG_P, 'csfxRepair()') end
  end
end

function M.buffOut()
  for _, veh in ipairs(getAllVehicles()) do
    if hasCanvas(veh) then veh:queueJSUITexture(TAG_B, 'csfxClear()'); veh:queueJSUITexture(TAG_P, 'csfxClear()') end
  end
end

-- carSurfaceFx_scratch.buffOut(): every car's scratches and splats gone
-- console helper: what each spawned car ended up with
function M.status()
  for _, veh in ipairs(getAllVehicles()) do
    local id = veh:getId()
    local car = cars[id]
    local s = not car and 'not set up (not the player car, or the feature is off)' or car.building and 'reading its mesh...'
      or car.none or ('ready - %d body nodes mapped onto the paint'):format(car.count)
    log('I', logTag, ('vehicle %d (%s): %s'):format(id, tostring(veh.JBeam), s))
  end
end

-- drop a few test scratches + dirt on the player car without needing a crash (console / Debug tab)
function M.test()
  local veh = getPlayerVehicle(0)
  local car = veh and cars[veh:getId()]
  if not car or not car.lut then log('W', logTag, 'player car is not set up yet - see carSurfaceFx_scratch.status()'); return end
  local ids = tableKeys(car.lut)
  for i = 1, 60 do M.hit(veh:getId(), ids[random(#ids)], 4000 + random() * 12000, 3 + random() * 10, random() - 0.5, random() - 0.5, (random() - 0.5) * 0.4) end
  for wi in pairs(car.wheels or {}) do for i = 1, 6 do M.wheelDirt(veh:getId(), wi) end end
end

-- ---- lifecycle ----
function M.onExtensionLoaded() end
local pollTimer = 0
function M.onUpdate(dt)
  carSurfaceFx_meshuv.tick()
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
end
function M.onVehicleSpawned(id)
  cars[id] = nil                                              -- new parts = new mesh; its canvases died with the old car
  ensureCanvases()
end
function M.onVehicleDestroyed(id) cars[id] = nil end
function M.onClientEndMission()   restoreAll() end
function M.onExtensionUnloaded()  restoreAll() end

return M
