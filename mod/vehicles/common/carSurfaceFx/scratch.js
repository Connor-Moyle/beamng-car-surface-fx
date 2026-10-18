// Car Surface FX - scratch, splat and rain-drop paint canvas (from Enhanced Skid Marks, changed to keep scratches and dirt splats apart and to run water drops over the
// paint). Runs inside a per-vehicle web texture; every vehicle that gets marks has TWO of these pages, told apart by the ?m= in the URL:
//   ?m=b  the paint layer's BASE COLOUR map. starts white; marks are drawn in their real colour.
//   ?m=p  the paint layer's COLOUR PALETTE map. starts solid red (= "paint colour 1 everywhere");
//         marks are ERASED from it, because the shader shows the base colour un-tinted wherever
//         the palette's alpha is gone.
// GE lua (carSurfaceFx/scratch.lua) works out every position and size and sends the SAME call to
// both pages, so the two always line up. Coordinates are 0..1 across the canvas.
// The page remembers its scratches and its splats as two lists. Washing fades the splat list and redraws, so the scratches come back untouched;
// repair empties the scratch list and redraws, so the dirt stays. New marks are drawn straight on top; a redraw puts the splats over the scratches.
// Everything permanent is drawn on an off-screen canvas; the visible canvas is that plus, on the base page, the running rain drops (paintwater.js) on top, redrawn
// only when something changed or a drop is moving.

(function () {
  var canvas = document.getElementById('csfxScratchCanvas');
  var ctx = canvas.getContext('2d');
  var palette = /[?&]m=p/.test(location.search);
  var dark = /[?&]dark=1/.test(location.search);   // this car has no palette to punch through: marks can only darken
  var W = canvas.width = canvas.height = 1024;
  var MAX_LINES = 300, MAX_BLOBS = 900;
  var lines = [];                                   // { l: [x1,y1,x2,y2,width, ...], c, a } as received
  var blobs = [];                                   // { x, y, r, c, a, k } k = 'dust' | 'mud'

  var sc = document.createElement('canvas');         // the permanent marks
  sc.width = sc.height = W;
  var sctx = sc.getContext('2d');
  var dirty = true;

  // the engine reads this texture as LINEAR colour, so a plain sRGB value comes out washed-out: pre-darken it
  function ch(x) { return Math.round(Math.pow(Math.max(0, Math.min(1, x)), 2.2) * 255); }
  function rgba(c, a) { return 'rgba(' + ch(c[0]) + ',' + ch(c[1]) + ',' + ch(c[2]) + ',' + a + ')'; }
  // base page: paint in colour c. palette page: punch the same shape out instead.
  // the base goes on much heavier than the punch-out: what shows is base x (white..paint by what's left of
  // the palette), so any white left in the base under a part-erased palette reads as chalky, not as the colour.
  function ink(c, a) {
    if (!palette) a = 1 - Math.pow(1 - a, 4);
    sctx.globalCompositeOperation = palette ? 'destination-out' : 'source-over';
    sctx.strokeStyle = sctx.fillStyle = palette ? 'rgba(0,0,0,' + a + ')' : rgba(c, a);
  }

  function blank() {
    sctx.globalCompositeOperation = 'source-over';
    sctx.fillStyle = palette ? '#f00' : '#fff';
    sctx.fillRect(0, 0, W, W);
    dirty = true;
  }

  // each scratch is a dark soft edge with the real colour down the middle, so it reads on light AND dark paint.
  function drawLines(o) {
    sctx.lineCap = 'round';
    for (var pass = 0; pass < 2; pass++) {
      var edge = pass === 0;
      var k = dark ? 0.12 : (edge ? 0.3 : 1);
      ink([o.c[0] * k, o.c[1] * k, o.c[2] * k], edge ? o.a * 0.5 : o.a);
      for (var i = 0; i < o.l.length; i += 5) {
        sctx.lineWidth = Math.max(1, o.l[i + 4] * W) + (edge ? 1.5 : 0);
        sctx.beginPath();
        sctx.moveTo(o.l[i] * W, o.l[i + 1] * W);
        sctx.lineTo(o.l[i + 2] * W, o.l[i + 3] * W);
        sctx.stroke();
      }
    }
    dirty = true;
  }

  // soft-edged dirt splats. base page ONLY: dirt just darkens/tints the paint. punching the palette too exposes the bare layer, which is as shiny as metal -
  // right for a scratch, but it made dirt look like chrome with a dark rim.
  // a number 0..1 from a place and an index, the same every time (a redraw must give the same splatter)
  function hash(x, y, i) { var h = Math.sin(x * 12.9898 + y * 78.233 + i * 37.719) * 43758.5453; return h - Math.floor(h); }
  function drawBlob(b) {
    if (palette) return;
    sctx.globalCompositeOperation = 'source-over';
    var x = b.x * W, y = b.y * W, r = Math.max(2, b.r * W);
    if (b.k === 'dust') {                                             // dust and snow: soft patches
      var g = sctx.createRadialGradient(x, y, r * 0.2, x, y, r);
      g.addColorStop(0, rgba(b.c, b.a)); g.addColorStop(1, rgba(b.c, 0));
      sctx.fillStyle = g;
      sctx.beginPath(); sctx.arc(x, y, r, 0, Math.PI * 2); sctx.fill();
    } else {                                                          // mud and bugs: a splat with a broken edge and droplets thrown around it
      var i, n = 4 + Math.floor(hash(b.x, b.y, 0) * 3);
      sctx.fillStyle = rgba(b.c, b.a * 0.55);
      for (i = 0; i < n; i++) {
        var ang = hash(b.x, b.y, i + 1) * 6.2832, d = r * 0.5 * hash(b.x, b.y, i + 9), rr = r * (0.35 + 0.45 * hash(b.x, b.y, i + 17));
        sctx.beginPath(); sctx.arc(x + Math.cos(ang) * d, y + Math.sin(ang) * d, rr, 0, Math.PI * 2); sctx.fill();
      }
      sctx.fillStyle = rgba(b.c, b.a * 0.9);
      for (i = 0; i < 3 + Math.floor(hash(b.x, b.y, 30) * 4); i++) {
        var a2 = hash(b.x, b.y, i + 40) * 6.2832, d2 = r * (1 + 1.3 * hash(b.x, b.y, i + 50)), r2 = Math.max(1, r * (0.07 + 0.16 * hash(b.x, b.y, i + 60)));
        sctx.beginPath(); sctx.arc(x + Math.cos(a2) * d2, y + Math.sin(a2) * d2, r2, 0, Math.PI * 2); sctx.fill();
      }
    }
    dirty = true;
  }

  function redraw() {
    blank();
    for (var i = 0; i < lines.length; i++) drawLines(lines[i]);
    for (var j = 0; j < blobs.length; j++) drawBlob(blobs[j]);
  }

  // o = { l: [x1,y1,x2,y2,width, ...], c: [r,g,b], a }
  window.csfxLines = function (o) {
    lines.push(o);
    if (lines.length > MAX_LINES) { lines.shift(); redraw(); return; }
    drawLines(o);
  };

  // o = { l: [x,y,radius, ...], c: [r,g,b], a, k: 'dust' | 'mud' }
  window.csfxBlobs = function (o) {
    for (var i = 0; i < o.l.length; i += 3) {
      var b = { x: o.l[i], y: o.l[i + 1], r: o.l[i + 2], c: o.c, a: o.a, k: o.k || 'mud' };
      blobs.push(b);
      drawBlob(b);
    }
    if (blobs.length > MAX_BLOBS) { blobs.splice(0, blobs.length - MAX_BLOBS); redraw(); }
  };

  // o = { dust: f, mud: f }: every splat's opacity times f (0..1); the ones that are nearly gone are dropped. The scratches are redrawn as they were.
  window.csfxWash = function (o) {
    var keep = [];
    for (var i = 0; i < blobs.length; i++) {
      var b = blobs[i], f = o[b.k] === undefined ? 1 : o[b.k];
      b.a *= f;
      if (b.a > 0.04) keep.push(b);
    }
    blobs = keep;
    redraw();
  };

  // scratches buffed out, the dirt stays
  window.csfxRepair = function () { lines = []; redraw(); };

  // everything gone
  window.csfxClear = function () { lines = []; blobs = []; redraw(); };

  // a big red cross over the whole canvas, to see whether this page reaches the paint at all (carSurfaceFx_scratch.probe())
  window.csfxProbe = function () { lines.push({ l: [0.05, 0.05, 0.95, 0.95, 0.06, 0.95, 0.05, 0.05, 0.95, 0.06], c: [1, 0, 0], a: 1 }); redraw(); };

  // ---- rain drops running over the paint (base page only: the palette page just shows the marks) ----
  var water = (typeof CsfxPaintWater !== 'undefined') ? CsfxPaintWater.create() : null;     // paintwater.js missing: scratches and splats still work
  var wp = { rain: 0, wet: 0, fx: 0, fy: 0, fz: -9.8 };
  var live = 0, last = performance.now(), rate = 0;
  var DR = 24, drop = document.createElement('canvas');            // one drop: a faint dark body, a darker rim, lower right darker still (what multiplies the paint colour)
  drop.width = drop.height = DR;
  (function () {
    var c = drop.getContext('2d'), data = c.createImageData(DR, DR);
    for (var y = 0; y < DR; y++) for (var x = 0; x < DR; x++) {
      var u = (x + 0.5) / DR * 2 - 1, v = (y + 0.5) / DR * 2 - 1, d2 = u * u + v * v, o = (y * DR + x) * 4;
      var d = Math.sqrt(d2);
      var ring = d < 1 ? Math.max(0, 1 - Math.abs(d - 0.8) / 0.25) : 0;
      var shade = Math.min(0.9, ring * (0.5 + 0.4 * Math.max(0, (u + v) * 0.7)) + (d < 1 ? 0.3 + 0.15 * Math.max(0, (u + v) * 0.7) : 0));
      data.data[o] = data.data[o + 1] = data.data[o + 2] = 0;
      data.data[o + 3] = Math.min(255, shade * 255 * Math.min(1, (1 - d) * 5 + 0.0));
    }
    c.putImageData(data, 0, 0);
  })();

  var wdebug = 0;
  window.csfxDebug = function (v) { wdebug = v; dirty = true; };                  // 1: the body nodes as red dots and the drops as big green discs, to see what reaches the paint
  var acc = [];
  var tc = document.createElement('canvas');                         // wet trails: white = nothing, dark where a drop has run, fading back to white
  tc.width = tc.height = W;
  var tctx = tc.getContext('2d');
  tctx.fillStyle = '#fff'; tctx.fillRect(0, 0, W, W);
  var trailLive = 0;
  var tpx = new Float32Array(water ? water.n : 0), tpy = new Float32Array(water ? water.n : 0), tseen = new Uint8Array(water ? water.n : 0);      // where each moving drop was at the last frame
  window.csfxNodes = function (rows, more) {                                      // the node map comes in pieces (a long script string may not get through): the first piece starts it over
    if (!more) acc = [];
    for (var i = 0; i < rows.length; i++) acc.push(rows[i]);
    if (water) CsfxPaintWater.setNodes(water, acc);
    dirty = true;
  };
  var gotWater = 0;
  window.csfxWater = function (o) { gotWater++; for (var k in o) if (typeof o[k] === 'number' && isFinite(o[k])) wp[k] = o[k]; };
  window.csfxInfo = function () { return water ? 'nodes ' + water.count + ' drops ' + CsfxPaintWater.alive(water) + ' rain ' + wp.rain : 'no water sim'; };

  var minMs = 0;                                                    // 0: work on every frame the browser gives; csfxThrottle(80) works at most every 80 ms (the texture is only taken at FPS)
  window.csfxThrottle = function (ms) { minMs = Number(ms) > 0 ? Number(ms) : 0; };
  function frame(now) {
    requestAnimationFrame(frame);                                  // first: whatever goes wrong below, the next frame still comes
    if (minMs && now - last < minMs) return;
    var dt = Math.min((now - last) / 1000, 0.2); last = now;
    if (dt > 0) rate += (1 / dt - rate) * 0.1;                      // how often the browser really calls this page (shown in the debug text)
    try {
      if (!palette && water && water.nodes) {
        if (wdebug) { wp.rain = 1; wp.wet = 1; }                                         // debug: rain on, whatever the game side says
        CsfxPaintWater.step(water, dt, wp);
        live = CsfxPaintWater.alive(water);
      }
    } catch (e) { window.csfxError = 'step ' + String(e); water = null; }
    if (!(dirty || live > 0 || window.csfxWasLive || wdebug)) return;
    ctx.globalCompositeOperation = 'source-over';
    ctx.drawImage(sc, 0, 0);
    dirty = false;
    window.csfxWasLive = live > 0 || trailLive > 0;                // a few more frames after the last drop is gone, to wipe it from the picture
    if (palette || !water) return;
    try {                                                           // trails: fade, add a dark dot where a drop moved, lay them over the paint (multiply: dark darkens, white changes nothing)
      tctx.globalCompositeOperation = 'source-over';
      // (written for 60 frames a second: at any other rate the fade is for the time that has passed, and a moving drop leaves a dot for every 1/60 s along its way,
      // so the trails look the same however often the browser calls this page)
      var steps = Math.max(1, Math.min(12, Math.round(dt * 60)));
      tctx.fillStyle = 'rgba(255,255,255,' + (1 - Math.pow(0.97, steps)) + ')'; tctx.fillRect(0, 0, W, W);
      var moving = 0;
      tctx.fillStyle = 'rgba(0,0,0,0.22)';
      for (var t = 0; t < water.n; t++) {
        if (!water.alive[t] || !water.moved[t]) { tseen[t] = 0; continue; }
        moving++;
        var rr = Math.max(1.0, water.r[t] * W * 0.7), cx = water.x[t] * W, cy = water.y[t] * W;
        for (var s = 1; s <= steps; s++) {
          var u = tseen[t] ? s / steps : 1;                         // from where it was, if it was moving a frame ago
          var dx = tseen[t] ? tpx[t] + (cx - tpx[t]) * u : cx, dy = tseen[t] ? tpy[t] + (cy - tpy[t]) * u : cy;
          tctx.beginPath(); tctx.arc(dx, dy, rr, 0, Math.PI * 2); tctx.fill();
          if (!tseen[t]) break;
        }
        tpx[t] = cx; tpy[t] = cy; tseen[t] = 1;
      }
      trailLive = moving > 0 ? 40 : Math.max(0, trailLive - steps);
      ctx.globalCompositeOperation = 'multiply';
      ctx.drawImage(tc, 0, 0);
      ctx.globalCompositeOperation = 'source-over';
    } catch (e) { window.csfxError = 'trail ' + String(e); }
    try {
      for (var i = 0; i < water.n; i++) {
        if (!water.alive[i]) continue;
        var R = Math.max(1.4, water.r[i] * W) * 1.3;                        // a 3 mm bead is about one texel: drawn at least this big
        ctx.drawImage(drop, water.x[i] * W - R, water.y[i] * W - R, R * 2, R * 2);
        if (wdebug) { ctx.fillStyle = 'rgb(0,0,0)'; ctx.beginPath(); ctx.arc(water.x[i] * W, water.y[i] * W, R * 0.5, 0, Math.PI * 2); ctx.fill(); }   // black: the base map MULTIPLIES the paint colour, so only dark shows on bright paint
      }
    } catch (e) { window.csfxError = 'drops ' + String(e); }
    if (!wdebug || !water.nodes) return;
    try {
      ctx.fillStyle = 'rgb(0,0,0)';
      for (var k = 0; k < water.count; k++) ctx.fillRect(water.nodes[k * 9] * W - 2, water.nodes[k * 9 + 1] * W - 2, 4, 4);
    } catch (e) { window.csfxError = 'dots ' + String(e); }
    try {                                                           // what the page knows, written at body nodes (which are on visible paint)
      ctx.font = 'bold 30px sans-serif'; ctx.fillStyle = 'rgb(0,0,0)';
      var txt = 'v15 n' + water.count + ' d' + live + ' r' + String(wp.rain) + ' f' + String(wp.fz) + ' g' + gotWater + ' fps' + Math.round(rate) + (window.csfxError ? ' ERR ' + window.csfxError : '');
      for (var tk = 0; tk < water.count; tk += Math.max(1, Math.floor(water.count / 14))) ctx.fillText(txt, water.nodes[tk * 9] * W, water.nodes[tk * 9 + 1] * W);
    } catch (e) { window.csfxError = 'text ' + String(e); }
  }
  blank();
  requestAnimationFrame(frame);
})();
