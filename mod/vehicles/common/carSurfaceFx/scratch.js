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
  var paintLum = 0.5;                               // how light the car's paint is (0 black .. 1 white): the lit mud is stronger on dark paint, where it is lighter than the paint
  var emis = /[?&]m=e/.test(location.search);       // the emissive page: only the dirt's own colour on black, added to the paint as light (the colour map can only darken)
  var dark = /[?&]dark=1/.test(location.search);   // this car has no palette to punch through: marks can only darken
  var W = canvas.width = canvas.height = 1024;
  var MAX_LINES = 300, MAX_BLOBS = 6000;
  var lines = [];                                   // { l: [x1,y1,x2,y2,width, ...], c, a } as received
  var blobs = [];                                   // { x, y, r, c, a, k } k = 'dust' | 'mud'

  var sc = document.createElement('canvas');         // the permanent marks
  sc.width = sc.height = W;
  var sctx = sc.getContext('2d');
  var dirty = true;

  // the engine reads this texture as LINEAR colour, so a plain sRGB value comes out washed-out: pre-darken it
  function ch(x) { return Math.round(Math.pow(Math.max(0, Math.min(1, x)), 2.2) * 255); }
  function rgbaColour(c, a) { return 'rgba(' + ch(c[0]) + ',' + ch(c[1]) + ',' + ch(c[2]) + ',' + a + ')'; }
  var rgba = rgbaColour;
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
    sctx.fillStyle = palette ? '#f00' : (emis ? '#000' : '#fff');
    sctx.fillRect(0, 0, W, W);
    dirty = true;
  }

  // a scratch stamp (4 columns x 8 rows of 256 x 128, the scratch runs along x) along every segment of a mark: the variant by place, thickness by the mark's width
  function drawStamps(o, img) {
    sctx.globalCompositeOperation = palette ? 'destination-out' : 'source-over';
    for (var i = 0; i < o.l.length; i += 5) {
      var x1 = o.l[i] * W, y1 = o.l[i + 1] * W, x2 = o.l[i + 2] * W, y2 = o.l[i + 3] * W, len = Math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
      if (len < 2) continue;
      var v = Math.floor(hash(o.l[i], o.l[i + 1], 3) * 32), th = Math.max(6, o.l[i + 4] * W * 5);
      sctx.save();
      sctx.globalAlpha = Math.min(1, o.a);
      sctx.translate((x1 + x2) / 2, (y1 + y2) / 2); sctx.rotate(Math.atan2(y2 - y1, x2 - x1));
      sctx.drawImage(img, (v % 4) * 256, Math.floor(v / 4) * 128, 256, 128, -len * 0.6, -th / 2, len * 1.2, th);
      sctx.restore();
    }
    dirty = true;
  }

  // each scratch is a dark soft edge with the real colour down the middle, so it reads on light AND dark paint.
  function drawLines(o) {
    if (emis) return;
    sctx.lineCap = 'round';
    var stamps = atlasFor('scratch', 1);                           // real scratches (art/surfacefx/splats/scratch.png): a stamp along each segment instead of a plain line
    for (var pass = 0; pass < 2; pass++) {
      if (pass === 1 && stamps) { drawStamps(o, stamps); continue; }
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
  // On the palette page the same splat is punched out of the palette (the paint's tint goes where the dirt is, so the dirt shows in ITS colour, not multiplied with the paint:
  // brown mud on dark blue paint is invisible when it can only darken, and pale dust cannot lighten at all). Both pages draw the same shapes.
  // Real splat pictures (art/surfacefx/splats/<kind>.png, made by tools/make_real_splats.py from CC0 photographs, see docs/TEXTURE_CREDITS.md): 4 x 4 variants of 256 px, RGBA.
  // Until a picture has loaded (or if it is missing) the splat is drawn the procedural way below, and the page redraws when it arrives.
  var SPLAT_KINDS = { mud: 1, dust: 1, snow: 1, grime: 1, rubber: 1 }, atlases = {};
  function atlasFor(kind) {
    var a = atlases[kind];
    if (a === undefined && typeof Image === 'undefined') return null;
    if (a === undefined) {
      a = atlases[kind] = { img: new Image(), ok: false };
      a.img.onload = function () { a.ok = true; dirty = true; redraw(); };
      a.img.onerror = function () { a.bad = true; };
      a.img.src = 'local://local/art/surfacefx/splats/' + kind + '.png?v=1';
    }
    return a.ok ? a.img : null;
  }
  // one real splat: a variant (by place, so a redraw gives the same splat), turned, drawn about r across. Base page: the picture's own colour; palette page: its alpha punches the palette;
  // lit page: the colour at a fraction of its brightness, the lit mud and dust of the paint (snow stays white).
  function drawReal(b, img) {
    var v = Math.floor(hash(b.x, b.y, 5) * 16), x = b.x * W, y = b.y * W, r = Math.max(2, b.r * W);
    var ang = (b.dx || b.dy) ? Math.atan2(b.dy, b.dx) + Math.PI / 2 + (hash(b.x, b.y, 6) - 0.5) * 0.6 : hash(b.x, b.y, 7) * 6.2832;
    var litDust = emis && b.t === 'dust';                                // lit dust: wide, faint and dim, so it is an even film on every paint and never a white dot
    var size = r * (b.t === 'mud' ? 2.6 : litDust ? 3.4 : 2.2), stretch = (b.dx || b.dy) ? 1.35 : 1;
    sctx.save();
    sctx.globalCompositeOperation = palette ? 'destination-out' : 'source-over';
    sctx.globalAlpha = Math.min(1, b.a * (litDust ? 0.22 : emis ? (b.t === 'snow' ? 1 : 0.6 * (0.7 + 0.6 * (1 - paintLum))) : 1));
    if (litDust) sctx.filter = 'brightness(0.45)';
    else if (emis && b.t !== 'snow') sctx.filter = 'brightness(' + (0.5 * (0.8 + 0.8 * (1 - paintLum))).toFixed(2) + ')';
    sctx.translate(x, y); sctx.rotate(ang); sctx.scale(1, stretch);
    // the base page is drawn heavier than the palette's punch (as ink() does for the plain splats): under a part-erased palette any white left in the base reads as a pale ring or dot, worst on dark paint
    var passes = (palette || emis) ? 1 : 3;
    for (var q = 0; q < passes; q++) sctx.drawImage(img, (v % 4) * 256, Math.floor(v / 4) * 256, 256, 256, -size / 2, -size / 2, size, size);
    sctx.restore();
    dirty = true;
  }

  function drawBlob(b) {
    if (b.t && SPLAT_KINDS[b.t] && b.k !== 'cake') { var at = atlasFor(b.t); if (at) { drawReal(b, at); return; } }
    sctx.globalCompositeOperation = palette ? 'destination-out' : 'source-over';
    var rgba = palette ? function (c, a) { return 'rgba(0,0,0,' + a + ')'; } : rgbaColour;
    if (emis && b.k === 'dust') b = { x: b.x, y: b.y, r: b.r, c: b.c, a: b.a > 0.2 ? b.a * 0.25 : b.a * 1.8, k: 'dust' };      // lit dust: the patches stay faint so the whole-car haze makes a film, not spots of light
    if (emis && b.k !== 'dust') {                                        // lit mud: as light the earth colours are far too bright and saturated (orange): darker and browner, every splat a little different, soft edges
      var mean = (b.c[0] + b.c[1] + b.c[2]) / 3, tone = 0.8 + 0.4 * hash(b.y, b.x, 77), thick = (0.6 + 0.75 * hash(b.x, b.y, 91)) * (0.8 + 0.8 * (1 - paintLum)), kk = 0.26 * tone * (1 + 0.9 * (1 - paintLum));
      b = { x: b.x, y: b.y, r: b.r, dx: b.dx, dy: b.dy, k: b.k, a: Math.min(1, b.a * thick * (b.k === 'cake' ? 0.8 : 1)), c: [(mean + (b.c[0] - mean) * 0.55) * kk, (mean + (b.c[1] - mean) * 0.55) * kk, (mean + (b.c[2] - mean) * 0.55) * kk] };
      sctx.filter = 'blur(1.3px)';
    }
    var x = b.x * W, y = b.y * W, r = Math.max(2, b.r * W);
    if (b.k === 'dust') {                                             // dust and snow: soft patches
      var g = sctx.createRadialGradient(x, y, r * 0.2, x, y, r);
      g.addColorStop(0, rgba(b.c, b.a)); g.addColorStop(1, rgba(b.c, 0));
      sctx.fillStyle = g;
      sctx.beginPath(); sctx.arc(x, y, r, 0, Math.PI * 2); sctx.fill();
    } else if (b.k === 'cake') {                                      // a clod of mud: a dark ring of lumps, a lighter lumpy top lit from up left, a few thrown droplets
      var nl2 = 6 + Math.floor(hash(b.x, b.y, 0) * 4), q;
      var rim = [b.c[0] * 0.45, b.c[1] * 0.45, b.c[2] * 0.45], top = [Math.min(1, b.c[0] * 1.15), Math.min(1, b.c[1] * 1.12), Math.min(1, b.c[2] * 1.1)];
      for (q = 0; q < nl2; q++) {
        var qa = hash(b.x, b.y, q + 1) * 6.2832, qd = r * 0.45 * hash(b.x, b.y, q + 9), qr = r * (0.42 + 0.4 * hash(b.x, b.y, q + 17));
        sctx.fillStyle = rgba(rim, b.a);
        sctx.beginPath(); sctx.arc(x + Math.cos(qa) * qd, y + Math.sin(qa) * qd, qr, 0, Math.PI * 2); sctx.fill();
      }
      for (q = 0; q < nl2; q++) {
        var qa2 = hash(b.x, b.y, q + 1) * 6.2832, qd2 = r * 0.45 * hash(b.x, b.y, q + 9), qr2 = r * (0.42 + 0.4 * hash(b.x, b.y, q + 17)) * 0.72;
        sctx.fillStyle = rgba(b.c, b.a);
        sctx.beginPath(); sctx.arc(x + Math.cos(qa2) * qd2 - r * 0.06, y + Math.sin(qa2) * qd2 - r * 0.06, qr2, 0, Math.PI * 2); sctx.fill();
      }
      sctx.fillStyle = rgba(top, b.a * 0.7);
      sctx.beginPath(); sctx.arc(x - r * 0.22, y - r * 0.25, r * 0.28, 0, Math.PI * 2); sctx.fill();
      sctx.fillStyle = rgba(rim, b.a * 0.9);
      for (q = 0; q < 3 + Math.floor(hash(b.x, b.y, 30) * 4); q++) {
        var qa3 = hash(b.x, b.y, q + 40) * 6.2832, qd3 = r * (1 + 0.9 * hash(b.x, b.y, q + 50)), qr3 = Math.max(1, r * (0.06 + 0.12 * hash(b.x, b.y, q + 60)));
        sctx.beginPath(); sctx.arc(x + Math.cos(qa3) * qd3, y + Math.sin(qa3) * qd3, qr3, 0, Math.PI * 2); sctx.fill();
      }
    } else if (b.dx || b.dy) {                                        // sprayed mud: an elongated splat along the spray, a tail of droplets behind it and a few ahead
      var ang = Math.atan2(b.dy, b.dx), j;
      sctx.fillStyle = rgba(b.c, b.a * 0.8);
      sctx.beginPath(); sctx.ellipse(x, y, r * 1.7, r * 0.7, ang, 0, Math.PI * 2); sctx.fill();
      sctx.fillStyle = rgba(b.c, b.a * 0.65);
      for (j = 1; j <= 4; j++) {                                      // the streak: smaller and smaller drops back along the line the spray came from
        var t = j * (0.9 + 0.5 * hash(b.x, b.y, j)), jr = Math.max(1, r * (0.55 - 0.1 * j));
        sctx.beginPath(); sctx.arc(x - Math.cos(ang) * r * t, y - Math.sin(ang) * r * t + (hash(b.x, b.y, j + 9) - 0.5) * r * 0.6, jr, 0, Math.PI * 2); sctx.fill();
      }
      sctx.fillStyle = rgba(b.c, b.a * 0.9);
      for (j = 0; j < 2 + Math.floor(hash(b.x, b.y, 3) * 3); j++) {
        var f = 1.5 + 1.6 * hash(b.x, b.y, j + 20);
        sctx.beginPath(); sctx.arc(x + Math.cos(ang) * r * f + (hash(b.x, b.y, j + 30) - 0.5) * r, y + Math.sin(ang) * r * f + (hash(b.x, b.y, j + 40) - 0.5) * r, Math.max(1, r * 0.18), 0, Math.PI * 2); sctx.fill();
      }
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
    if (emis) sctx.filter = 'none';
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
  var callCount = 0;
  window.csfxBlobs = function (o) {
    callCount++;
    for (var i = 0; i < o.l.length; i += 3) {
      var b = { x: o.l[i], y: o.l[i + 1], r: o.l[i + 2], c: o.c, a: o.a, k: o.k || 'mud', t: o.t };
      if (o.d) { b.dx = o.d[(i / 3) * 2]; b.dy = o.d[(i / 3) * 2 + 1]; }                  // the direction of the spray on the texture, when there is one
      blobs.push(b);
      drawBlob(b);
    }
    if (blobs.length > MAX_BLOBS) { blobs.splice(0, blobs.length - MAX_BLOBS); redraw(); }
  };

  // o = { dust: f, mud: f }: every splat's opacity times f (0..1); the ones that are nearly gone are dropped. The scratches are redrawn as they were.
  window.csfxWash = function (o) {
    var keep = [];
    for (var i = 0; i < blobs.length; i++) {
      var b = blobs[i], f = o[b.k === 'cake' ? 'mud' : b.k] === undefined ? 1 : o[b.k === 'cake' ? 'mud' : b.k];
      b.a *= f;
      if (b.a > 0.04) keep.push(b);
    }
    blobs = keep;
    redraw();
  };

  // scratches buffed out, the dirt stays
  window.csfxRepair = function () { lines = []; redraw(); };

  // everything gone
  window.csfxPaintLum = function (v) { v = Number(v); if (isFinite(v) && Math.abs(v - paintLum) > 0.04) { paintLum = Math.max(0, Math.min(1, v)); if (emis) redraw(); } };

  window.csfxClear = function () { lines = []; blobs = []; redraw(); };

  // a big red cross over the whole canvas, to see whether this page reaches the paint at all (carSurfaceFx_scratch.probe())
  window.csfxProbe = function () {
    lines.push({ l: [0.05, 0.05, 0.95, 0.95, 0.06, 0.95, 0.05, 0.05, 0.95, 0.06], c: [1, 0, 0], a: 1 }); redraw();
    // and what this page holds, written large over the map in several places: blobs kept, calls received so far
    sctx.globalCompositeOperation = palette ? 'destination-out' : 'source-over'; sctx.fillStyle = palette ? '#000' : '#f00'; sctx.font = 'bold 110px sans-serif';
    for (var ty = 1; ty <= 9; ty += 2) sctx.fillText('blobs ' + blobs.length + ' calls ' + callCount, 20, ty * 100);
    dirty = true;
  };

  // ---- rain drops running over the paint (base page only: the palette page just shows the marks) ----
  var water = (typeof CsfxPaintWater !== 'undefined' && !emis) ? CsfxPaintWater.create() : null;     // paintwater.js missing: scratches and splats still work
  var wp = { rain: 0, wet: 0, fx: 0, fy: 0, fz: -9.8 };
  var live = 0, last = performance.now(), rate = 0;
  // One drop, for the base colour map (which MULTIPLIES the paint colour: it can only darken): water is clear, so the body is left alone; what shows is the thin dark edge of
  // the bead, heavier on its lower right (the drop is a lens that bends the dark ground into it there). The earlier sprite had a dark body and read as black spots.
  var DR = 24, drop = document.createElement('canvas');
  drop.width = drop.height = DR;
  (function () {
    var c = drop.getContext('2d'), data = c.createImageData(DR, DR);
    for (var y = 0; y < DR; y++) for (var x = 0; x < DR; x++) {
      var u = (x + 0.5) / DR * 2 - 1, v = (y + 0.5) / DR * 2 - 1, d2 = u * u + v * v, o = (y * DR + x) * 4;
      var d = Math.sqrt(d2);
      var ring = d < 1.05 ? Math.max(0, 1 - Math.abs(d - 0.82) / 0.2) : 0;
      var low = Math.max(0, Math.min(1, (u + v) * 0.7));
      data.data[o] = data.data[o + 1] = data.data[o + 2] = 0;
      data.data[o + 3] = Math.min(255, ring * (0.3 + 0.35 * low) * 255);
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

  var imp = [], IMP_LIFE = 0.6;                                       // raindrop impacts: [x, y, age] rings that open and fade in about 0.3 s (3 frames at 10 a second)
  var minMs = 90;                                                   // the texture is only taken 10 times a second (FPS in scratch.lua): drawing more often is wasted work; csfxThrottle(0) draws on every frame the browser gives
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
      tctx.fillStyle = 'rgba(0,0,0,0.10)';                              // a wet trail darkens the paint only a little
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
      var rings = 0;
      ctx.strokeStyle = 'rgba(0,0,0,0.32)'; ctx.lineWidth = 0.7; ctx.beginPath();
      for (var i = 0; i < water.n; i++) {
        if (!water.alive[i]) continue;
        var R = Math.max(0.7, water.r[i] * W) * 1.15;                        // a 3 mm bead is about one texel across: drawn at its real size, not rounded up
        if (R < 1.8 && !wdebug) {                                           // too small for the sprite: a thin dark ring of that size (all the rings in one path, one stroke)
          var rx = water.x[i] * W, ry = water.y[i] * W;
          ctx.moveTo(rx + R, ry); ctx.arc(rx, ry, R, 0, Math.PI * 2); rings++;
        } else {
          ctx.drawImage(drop, water.x[i] * W - R, water.y[i] * W - R, R * 2, R * 2);
        }
        if (wdebug) { ctx.fillStyle = 'rgb(0,0,0)'; ctx.beginPath(); ctx.arc(water.x[i] * W, water.y[i] * W, R * 0.5, 0, Math.PI * 2); ctx.fill(); }   // black: the base map MULTIPLIES the paint colour, so only dark shows on bright paint
      }
      if (rings > 0) ctx.stroke();
    } catch (e) { window.csfxError = 'drops ' + String(e); }
    try {                                                           // impacts: a small ring opening where a raindrop landed (wp.imp: how many of the landings get one, 0 = none)
      var fr = water.fresh;
      for (var f = 0; f < fr.length && wp.imp > 0; f++) if (imp.length < 160 && Math.random() < wp.imp) imp.push([water.x[fr[f]] * W, water.y[fr[f]] * W, 0]);
      fr.length = 0;
      var kept = 0;
      for (var m = 0; m < imp.length; m++) {
        var im = imp[m]; im[2] += dt;
        if (im[2] >= IMP_LIFE) continue;
        var ph = im[2] / IMP_LIFE;
        ctx.strokeStyle = 'rgba(0,0,0,' + (0.45 * (1 - ph) + 0.05).toFixed(2) + ')'; ctx.lineWidth = 0.9;
        ctx.beginPath(); ctx.arc(im[0], im[1], 0.8 + 3.4 * ph, 0, Math.PI * 2); ctx.stroke();
        imp[kept++] = im;
      }
      imp.length = kept;
    } catch (e) { window.csfxError = 'impacts ' + String(e); }
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
