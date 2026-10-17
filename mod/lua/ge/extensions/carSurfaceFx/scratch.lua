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
local PAGE_V = 7                                              -- bumped with every change of scratch.html/.js/paintwater.js: the browser caches pages by their address, a new number loads the new files
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
  }
end
local settings = defaults()

-- what each car has been marked with, kept GE-side (the canvas pages are write-only for us): scratch lines { x1, y1, x2, y2, width } and dirt splats { x, y, r, opacity, kind }
-- (kind 1 = dust, 2 = mud), quantised and capped, so a car's marks can be saved (getState) and drawn again on a respawned car (restore, and after a mesh rebuild).
local memory, replayAt, nodesAt = {}, {}, {}
local MEMORY_CAP = 60
local function mem(id)
  local m = memory[id]
  if not m then m = { marks = {}, splats = {} } memory[id] = m end
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
        veh:createUITexture(TAG_B, PAGE .. (pal and '?m=b' or '?m=b&dark=1') .. '&v=' .. PAGE_V, SIZE, SIZE, UI_TEXTURE_USAGE_AUTOMATIC, FPS)
        veh:createUITexture(TAG_P, PAGE .. '?m=p&v=' .. PAGE_V, SIZE, SIZE, UI_TEXTURE_USAGE_AUTOMATIC, FPS)
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
    nodesAt[id] = os.clock() + 2                              -- the page gets the car's body-node map for the running drops once it is up
    if memory[id] then replayAt[id] = os.clock() + 2 end       -- a rebuilt car gets its marks drawn again once its pages are up
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
  local m = mem(id)
  for i = 1, #lines, 5 do remember(m.marks, { q(lines[i]), q(lines[i + 1]), q(lines[i + 2]), q(lines[i + 3]), q(lines[i + 4], 100000) }) end
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
  local m = mem(id)
  for i = 1, #blobs, 3 do remember(m.splats, { q(blobs[i]), q(blobs[i + 1]), q(blobs[i + 2], 10000), q(opacity or settings.dirtOpacity), kind == 'dust' and 1 or 2 }) end
end

-- washing: every splat's opacity times fDust / fMud (0..1) on car id (every car with canvases when id is nil). The scratches are not touched.
function M.washSplats(id, fDust, fMud)
  for _, veh in ipairs(getAllVehicles()) do
    if (id == nil or veh:getId() == id) and hasCanvas(veh) then
      local js = ('csfxWash({dust:%.4f,mud:%.4f})'):format(fDust, fMud)
      veh:queueJSUITexture(TAG_B, js); veh:queueJSUITexture(TAG_P, js)
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

-- repair: the scratches of car id buffed out (every car's when id is nil); the dirt stays
function M.repair(id)
  for _, veh in ipairs(getAllVehicles()) do
    if (id == nil or veh:getId() == id) and hasCanvas(veh) then veh:queueJSUITexture(TAG_B, 'csfxRepair()'); veh:queueJSUITexture(TAG_P, 'csfxRepair()') end
  end
  for vid, m in pairs(memory) do if id == nil or vid == id then m.marks = {} end end
end

function M.buffOut()
  memory = {}
  for _, veh in ipairs(getAllVehicles()) do
    if hasCanvas(veh) then veh:queueJSUITexture(TAG_B, 'csfxClear()'); veh:queueJSUITexture(TAG_P, 'csfxClear()') end
  end
end

-- how many scratches car id carries (the last MEMORY_CAP are remembered)
function M.count(id) local m = memory[id] return m and #m.marks or 0 end

-- the marks of car id as plain numbers (the last 40 scratch lines and splats), or nil
function M.getState(id)
  local m = memory[id]
  if not m or (#m.marks == 0 and #m.splats == 0) then return nil end
  local out = { marks = {}, splats = {} }
  for i = math.max(1, #m.marks - 39), #m.marks do out.marks[#out.marks + 1] = { unpack(m.marks[i]) } end
  for i = math.max(1, #m.splats - 39), #m.splats do out.splats[#out.splats + 1] = { unpack(m.splats[i]) } end
  return out
end

-- put marks back on car id (from getState): remembered now, drawn as soon as the car's canvases are up
function M.restore(id, st)
  local m = { marks = {}, splats = {} }
  for _, r in ipairs(type(st) == 'table' and st.marks or {}) do if #r >= 5 then m.marks[#m.marks + 1] = { r[1], r[2], r[3], r[4], r[5] } end end
  for _, r in ipairs(type(st) == 'table' and st.splats or {}) do if #r >= 5 then m.splats[#m.splats + 1] = { r[1], r[2], r[3], r[4], r[5] } end end
  memory[id] = m
  replayAt[id] = os.clock() + 1
end

local function replay(id)
  local m, veh = memory[id], getObjectByID(id)
  if not m or not veh then return end
  for i = 1, #m.marks, 10 do
    local l = {}
    for j = i, math.min(i + 9, #m.marks) do for k = 1, 5 do l[#l + 1] = m.marks[j][k] end end
    draw(veh, 'csfxLines', { l = l, c = settings.colour, a = settings.opacity * 0.8 })
  end
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
function M.water(id, p)
  local car, veh = cars[id], getObjectByID(id)
  if not (settings.water and car and car.lut and veh and hasCanvas(veh)) then return end
  -- the car's own left / back / up lines when its reference nodes give them, else the jbeam axes (x left, y back, z up: gravity is right either way)
  local ax = car.axes or { vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1) }
  local f = ax[1] * p.aLat + ax[2] * (p.aLong + p.speed * p.speed / 80) + ax[3] * -9.8
  veh:queueJSUITexture(TAG_B, ('csfxWater({rain:%.3f,wet:%.3f,fx:%.3f,fy:%.3f,fz:%.3f})'):format(p.rain, p.wet, f.x, f.y, f.z))
end

-- carSurfaceFx_scratch.waterDebug(true): the player car's paint shows its body nodes as red dots and the running drops as big green discs (and sends the node map again)
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
function M.probe()
  local veh = getPlayerVehicle(0)
  if not veh then return 'no player vehicle' end
  veh:queueJSUITexture(TAG_B, 'csfxProbe()'); veh:queueJSUITexture(TAG_P, 'csfxProbe()')
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
  for id, t in pairs(nodesAt) do
    local car, veh = cars[id], getObjectByID(id)
    if t <= os.clock() and car and car.lut and veh and hasCanvas(veh) then sendNodes(id) nodesAt[id] = nil end
  end
  for id, t in pairs(replayAt) do
    local car, veh = cars[id], getObjectByID(id)
    if t <= os.clock() and car and car.lut and veh and hasCanvas(veh) then replay(id) replayAt[id] = nil end
  end
end
function M.onVehicleSpawned(id)
  cars[id] = nil                                              -- new parts = new mesh; its canvases died with the old car
  ensureCanvases()
end
function M.onVehicleDestroyed(id) cars[id] = nil memory[id] = nil replayAt[id] = nil nodesAt[id] = nil end
function M.onClientEndMission()   restoreAll() end
function M.onExtensionUnloaded()  restoreAll() end

return M
