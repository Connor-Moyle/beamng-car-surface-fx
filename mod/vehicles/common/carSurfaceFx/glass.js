// Car Surface FX window canvas: this page IS one of the glass material's maps while the glass is wet. The game side puts in the URL which map it is:
//   ?mode=color&base=<path>  the base colour map: the glass's tint image first, the drops on top as light glints and dark edges
//   ?mode=emissive           the emissive map (the inside glass, which is clear: a colour change on it is invisible, and the engine does not resolve a '@tag' in its opacity
//                            map): black, with only the glints and bright rims of the drops, which add light whatever the glass opacity is
// The game side sends csfxSet({...}) a few times a second; this page runs the drops (sim.js) and draws every frame.
//   csfxSet({ tint: 0.5 })  darkens the colour map (if the glass looks milky), csfxSet({ passes: 2 }) = how often the image is squared to match the engine's linear reading.
(function () {
  var canvas = document.getElementById('csfx');
  var W = canvas.width = window.innerWidth || 512, H = canvas.height = window.innerHeight || 512;
  var ctx = canvas.getContext('2d');
  var sim = CsfxSim.create(1800);
  var p = { flow: null, frost: 0, rain: 0, wet: 0, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, tint: 1, passes: 1, flood: 0 };
  var last = performance.now();
  var q = function (name) { var m = new RegExp('[?&]' + name + '=([^&]*)').exec(location.search); return m ? decodeURIComponent(m[1]) : ''; };
  var emissive = q('mode') === 'emissive', basePath = q('base');

  // the background: the original tint image, squared 'passes' times (drawing the canvas over itself with 'multiply') because the engine reads a canvas as linear colour where a
  // png would be decoded from sRGB. Until the image has loaded, a dark tint stands in; the emissive canvas is black.
  var bg = document.createElement('canvas');
  bg.width = W; bg.height = H;
  var bctx = bg.getContext('2d');
  var img = null, builtPasses = -1;
  function buildBg() {
    builtPasses = p.passes;
    bctx.globalCompositeOperation = 'source-over';
    bctx.fillStyle = emissive ? 'rgb(0,0,0)' : 'rgb(20,20,20)';
    bctx.fillRect(0, 0, W, H);
    if (emissive || !img || !img.complete || !img.naturalWidth) return;
    bctx.drawImage(img, 0, 0, W, H);
    bctx.globalCompositeOperation = 'multiply';
    for (var i = 0; i < p.passes; i++) bctx.drawImage(bg, 0, 0);
    bctx.globalCompositeOperation = 'source-over';
  }
  buildBg();
  if (basePath && !emissive) {
    img = new Image();
    img.onload = buildBg;
    img.src = 'local://local/' + basePath.replace(/^\//, '');
  }

  // One drop as a bead, the way the body drops are drawn: a clear body, a thin dark edge (heavier low right) and one sharp glint up-left; no bright rim, which made the drops look
  // like bubbles. The colour map is drawn over the tinted glass image (it can lighten or darken it): the dark edge, the glint and a faint light spot low right that the drop
  // focuses (it lifts a dark tint). The emissive map ADDS light to the inside pane, which is clear: only light parts there, the glint and a narrow lit edge up-left.
  var S = 64, sprite = document.createElement('canvas');
  sprite.width = sprite.height = S;
  (function () {
    var c = sprite.getContext('2d'), data = c.createImageData(S, S);
    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {
      var u = (x + 0.5) / S * 2 - 1, v = (y + 0.5) / S * 2 - 1, d2 = u * u + v * v, o = (y * S + x) * 4;
      if (d2 >= 1.1) { data.data[o + 3] = 0; continue; }
      var d = Math.sqrt(d2);
      var ring = Math.max(0, 1 - Math.abs(d - 0.84) / 0.16);                       // a thin ring near the edge
      var low = Math.max(0, Math.min(1, (u + v) * 0.7));                           // toward the bottom right
      var gx = u + 0.38, gy = v + 0.42;
      var glint = Math.exp(-(gx * gx + gy * gy) / 0.014);
      var r, g, b, a;
      if (emissive) {
        var lit = ring * Math.max(0, Math.min(1, -(u + v) * 0.7)) * 0.2;           // a narrow lit edge on the upper left, faint: the body of a drop on the glass is clear
        a = Math.min(1, lit + glint * 0.85); r = g = b = 255;
      } else {
        var spot = d < 0.8 ? 0.14 * Math.exp(-((u - 0.25) * (u - 0.25) + (v - 0.3) * (v - 0.3)) / 0.12) : 0;      // light focused low right
        var dark = ring * (0.32 + 0.40 * low);
        // the dark edge, then the light parts over it (straight alpha out of the two layers)
        var lightA = Math.min(1, glint * 0.95 + spot);
        a = lightA + dark * (1 - lightA);
        var lum = a > 0 ? (255 * lightA) / a : 0;                                  // the colour is the light share of the result: white where light, black where dark
        r = g = b = lum;
      }
      data.data[o] = r; data.data[o + 1] = g; data.data[o + 2] = b;
      data.data[o + 3] = Math.min(255, a * 255);
    }
    c.putImageData(data, 0, 0);
  })();

  var frostTex = CsfxSim.frostTexture(document, 256);
  var frostLayer = document.createElement('canvas');                // the frost as it is now: the blade's band is cleared out of it and stays clear until the frost is gone
  frostLayer.width = frostLayer.height = 256;
  var fctx = frostLayer.getContext('2d'), frostFresh = false, wipePrev = 0;

  // the directions of this glass material's panes (carSurfaceFx/glassflow.lua), in pieces: csfxFlow('g' | 'b' | 'r', firstIndex, [numbers x 100])
  var FN = 32;
  window.csfxFlow = function (kind, start, arr) {
    var fl = p.flow;
    if (!fl) fl = p.flow = { n: FN, g: new Float32Array(FN * FN * 2), b: new Float32Array(FN * FN * 2), r: new Float32Array(FN * FN * 2), m: new Float32Array(FN * FN), cells: null, got: {}, ready: false };
    var dst = fl[kind];
    if (!dst) return;
    for (var i = 0; i < arr.length; i++) dst[start + i] = arr[i] / 100;
    if (start + arr.length >= dst.length) fl.got[kind] = true;
    fl.ready = !!(fl.got.g && fl.got.b && fl.got.r);
    if (kind === 'm' && fl.got.m) {                                   // the cells that are glass: drops are only made there
      var cells = [];
      for (var c = 0; c < fl.m.length; c++) if (fl.m[c] > 0.5) cells.push(c);
      fl.cells = cells.length ? cells : null;
      fl.rear = [];                                                   // the rear glass (2 in the mask): the dust film of a dirt road settles there
      for (var rc = 0; rc < fl.m.length; rc++) if (fl.m[rc] > 1.5) fl.rear.push(rc);
      filmBuilt = false;
    }
  };

  // the film on the rear glass: soft overlapping patches over the rear cells, drawn once and laid on with the amount
  var filmLayer = document.createElement('canvas'), filmBuilt = false;
  function buildFilm(fl) {
    filmLayer.width = W; filmLayer.height = H;
    var tmp = document.createElement('canvas'); tmp.width = W; tmp.height = H;
    var fc = tmp.getContext('2d'), cw = W / fl.n, ch = H / fl.n, i;
    for (i = 0; i < fl.rear.length; i++) {
      var cx = (fl.rear[i] % fl.n + 0.5) * cw, cy = (Math.floor(fl.rear[i] / fl.n) + 0.5) * ch, k = 0.8 + 0.2 * Math.abs(Math.sin(fl.rear[i] * 12.9898));
      fc.fillStyle = 'rgba(255,255,255,' + (0.8 * k).toFixed(2) + ')';                          // every rear cell filled, a little different: an even film, not blobs
      fc.fillRect(Math.round(cx - cw * 0.5), Math.round(cy - ch * 0.5), Math.round(cw), Math.round(ch));     // (no overlap: it would double the light along the seams)
    }
    var out = filmLayer.getContext('2d');
    out.clearRect(0, 0, W, H);
    try { out.filter = 'blur(' + Math.max(3, Math.round(cw * 0.6)) + 'px)'; } catch (e) {}                 // the seams between cells and the cell edges melt
    out.drawImage(tmp, 0, 0);
    out.filter = 'none';
    filmBuilt = true;
  }

  window.csfxSet = function (o) { for (var k in o) p[k] = o[k]; if (p.passes !== builtPasses) buildBg(); };
  window.csfxClear = function () { sim = CsfxSim.create(1800); };

  var imp = [], IMP_LIFE = 0.25;                                      // raindrop impacts: [x, y, age] rings that open and fade in a quarter second
  var minMs = 70;                                                   // the texture is only taken 12 times a second (GLASS_FPS in carSurfaceFx.lua): drawing more often is wasted work; csfxThrottle(0) draws on every frame the browser gives
  window.csfxThrottle = function (ms) { minMs = Number(ms) > 0 ? Number(ms) : 0; };
  function frame(now) {
    if (minMs && now - last < minMs) { requestAnimationFrame(frame); return; }
    var dt = Math.min((now - last) / 1000, 0.1); last = now;
    CsfxSim.step(sim, dt, p);
    ctx.globalCompositeOperation = 'source-over';
    ctx.drawImage(bg, 0, 0);
    if (p.flood > 0) { ctx.fillStyle = emissive ? 'rgb(255,255,255)' : 'rgb(255,0,0)'; ctx.fillRect(0, 0, W, H); }      // debug: the whole map solid, to see which surface uses it
    if (!emissive && p.tint < 1) { ctx.fillStyle = 'rgba(0,0,0,' + (1 - p.tint) + ')'; ctx.fillRect(0, 0, W, H); }
    // a drop of a few pixels: a thin ring and a one-pixel glint, all the rings in one path and all the glints in another (one stroke, one fill); bigger ones the sprite
    var tiny = false;
    ctx.strokeStyle = emissive ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.5)'; ctx.lineWidth = emissive ? 1 : 0.9;       // the emissive map adds light: a light ring there
    ctx.beginPath();
    var glints = [], dots = [];
    for (var i = 0; i < sim.n; i++) {
      if (!sim.alive[i]) continue;
      var R = sim.r[i] * H, px = sim.x[i] * W, py = sim.y[i] * H;
      if (R < 2.2) {
        var rr = Math.max(0.9, R);                                    // a bead is about one texel of this canvas: drawn at least 2.4 px across so it can be seen at all
        if (emissive) dots.push(px - rr * 0.8, py - rr * 0.8, rr * 1.6);      // a ring of 2 px rasterises as a plus and a lit plus is a star up close: on the light map a small drop is one soft lit square
        else { ctx.moveTo(px + rr, py); ctx.arc(px, py, rr, 0, Math.PI * 2); tiny = true; }
        glints.push(px - 0.35 * rr - 0.5, py - 0.4 * rr - 0.5);
      } else {
        ctx.drawImage(sprite, px - R, py - R, R * 2, R * 2);
      }
    }
    if (tiny) ctx.stroke();
    if (dots.length) { ctx.fillStyle = 'rgba(255,255,255,0.4)'; for (var di = 0; di < dots.length; di += 3) ctx.fillRect(dots[di], dots[di + 1], dots[di + 2], dots[di + 2]); }
    if (glints.length && !emissive) {      // the inside light map has no glints: at 4 mm a texel any lit mark of a drop reads as a white dot up close; the disc and the ring carry it
      ctx.fillStyle = 'rgba(255,255,255,' + (emissive ? 0.7 : 0.85) + ')';
      for (var gi = 0; gi < glints.length; gi += 2) ctx.fillRect(glints[gi], glints[gi + 1], 1.2, 1.2);
    }
    if (p.film > 0.02 && p.flow && p.flow.rear && p.flow.rear.length) {       // a dirt road's film on the rear glass: milky, from nothing to hazy
      if (!filmBuilt) buildFilm(p.flow);
      ctx.globalAlpha = Math.min(1, p.film * (emissive ? 1.1 : 0.45)); ctx.drawImage(filmLayer, 0, 0); ctx.globalAlpha = 1;
    }
    if (p.dbg == 2) {                                                 // glassDebug('drops'): only the live drops, eight times their size, solid white (or magenta on the colour map)
      ctx.globalCompositeOperation = 'source-over'; ctx.clearRect(0, 0, W, H); ctx.fillStyle = emissive ? 'rgb(255,255,255)' : 'rgb(255,0,255)';
      ctx.beginPath();
      for (var bi = 0; bi < sim.n; bi++) if (sim.alive[bi]) { var BR = Math.max(6, sim.r[bi] * H * 8); ctx.moveTo(sim.x[bi] * W + BR, sim.y[bi] * H); ctx.arc(sim.x[bi] * W, sim.y[bi] * H, BR, 0, Math.PI * 2); }
      ctx.fill();
    } else if (p.dbg) {                                                      // debug (carSurfaceFx.glassDebug(true)): the glass cells as light squares and what the page knows, written on the glass
      try {
        var flx = p.flow, n = flx && flx.n ? flx.n : 0, alive = 0;
        for (var di = 0; di < sim.n; di++) alive += sim.alive[di];
        if (flx && flx.cells) { ctx.fillStyle = emissive ? 'rgba(255,255,255,0.18)' : 'rgba(255,0,0,0.25)'; for (var ci = 0; ci < flx.cells.length; ci++) { var cc2 = flx.cells[ci]; ctx.fillRect((cc2 % n) * W / n, Math.floor(cc2 / n) * H / n, W / n - 1, H / n - 1); } }
        ctx.font = 'bold ' + Math.round(H / 12) + 'px sans-serif'; ctx.strokeStyle = emissive ? 'rgba(255,255,255,0.5)' : 'rgba(255,255,0,0.5)'; ctx.lineWidth = 1;       // the texture in 8 x 8 labelled squares (A1 top left): which squares a window shows says which part of the map it samples
        ctx.fillStyle = emissive ? 'rgb(255,255,255)' : 'rgb(255,255,0)';
        for (var lx = 0; lx < 8; lx++) for (var ly = 0; ly < 8; ly++) { ctx.strokeRect(lx * W / 8, ly * H / 8, W / 8, H / 8); ctx.fillText(String.fromCharCode(65 + lx) + (ly + 1), (lx + 0.12) * W / 8, (ly + 0.62) * H / 8); }
        ctx.font = 'bold 26px sans-serif'; ctx.fillStyle = emissive ? 'rgb(255,255,255)' : 'rgb(255,255,0)';
        var txt = 'drops ' + alive + ' flow ' + (flx ? (flx.ready ? 'ready' : 'partial') : 'none') + ' cells ' + (flx && flx.cells ? flx.cells.length : 0) + ' rain ' + Number(p.rain).toFixed(2) + ' mm ' + p.glassMm + ' uv/m ' + Number(p.uvPerM || 0).toFixed(2) + ' ' + W + 'x' + H;
        for (var ty = 0.15; ty < 1; ty += 0.3) ctx.fillText(txt, 6, ty * H);
      } catch (e) {}
    }
    var fr = sim.fresh;                                               // impacts: a quick small ring where a raindrop landed (p.imp: how many of the landings get one, 0 = none)
    for (var f = 0; f < fr.length && p.imp > 0; f++) if (imp.length < 60 && Math.random() < p.imp) imp.push([sim.x[fr[f]] * W, sim.y[fr[f]] * H, 0]);
    fr.length = 0;
    var kept = 0;
    for (var m = 0; m < imp.length; m++) {
      var im = imp[m]; im[2] += dt;
      if (im[2] >= IMP_LIFE) continue;
      var ph = im[2] / IMP_LIFE;
      ctx.strokeStyle = (emissive ? 'rgba(255,255,255,' : 'rgba(255,255,255,') + ((emissive ? 0.22 : 0.4) * (1 - ph)).toFixed(2) + ')'; ctx.lineWidth = 0.8;
      ctx.beginPath(); ctx.arc(im[0], im[1], 1 + 3 * ph, 0, Math.PI * 2); ctx.stroke();
      imp[kept++] = im;
    }
    imp.length = kept;
    if (p.frost < 0.05) frostFresh = false;
    else if (!frostFresh) { fctx.globalCompositeOperation = 'source-over'; fctx.clearRect(0, 0, 256, 256); fctx.drawImage(frostTex, 0, 0); frostFresh = true; }
    if (p.frost > 0.01 && p.wiper > 0.05 && sim.wipe !== wipePrev) {     // the blade's band, along the glass's axis (as in sim.js), is clear
      var a = Math.min(wipePrev, sim.wipe) - 0.03, b = Math.max(wipePrev, sim.wipe) + 0.03;
      if (-p.gy + p.gx < 0) { var t = 1 - b; b = 1 - a; a = t; }
      fctx.globalCompositeOperation = 'destination-out';
      if (Math.abs(p.gy) > Math.abs(p.gx)) fctx.fillRect(a * 256, 0, (b - a) * 256, 256); else fctx.fillRect(0, a * 256, 256, (b - a) * 256);
      fctx.globalCompositeOperation = 'source-over';
    }
    wipePrev = sim.wipe;
    if (p.frost > 0.01) {                                             // ice over the drops
      ctx.globalAlpha = Math.min(1, p.frost * 1.2) * (emissive ? 0.7 : 1);
      ctx.drawImage(frostLayer, 0, 0, W, H);
      ctx.globalAlpha = 1;
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
