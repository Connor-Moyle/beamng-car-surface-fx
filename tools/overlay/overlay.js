// The part of the windscreen rain overlay that is not the drop simulation (sim.js is put in front of it by tools/build_overlay.js into
// mod/ui/modModules/csfxRain/csfxRain.js). A global UI module of the game's web UI (the layer the Street Legal HUD uses): a transparent full-screen canvas that never takes
// the mouse; the game side (carSurfaceFx/screen.lua + carSurfaceFx.lua) sends 'csfxScreen' about 15 times a second while the driver's camera looks through a wet
// windscreen: { on, hull: [x1, y1, ...] (screen fractions), rain, wet, speed, aLong, aLat, wiper, size }. The drops are the window simulation, laid into the hull's bounding box and
// clipped to the hull. Each drop is drawn as a small lens (a sprite: faint film, lighter rim up-left, dark crescent down-right, a glint); a running drop leaves a thin wobbling
// streak on a second layer that fades slowly and is wiped clean along the wiper's sweep. Drawn at 30 frames a second at most.

function createOverlay(doc, win) {
  var root = doc.createElement('div');
  root.style.cssText = 'position:fixed;left:0;top:0;right:0;bottom:0;pointer-events:none;z-index:35;display:none';
  var canvas = doc.createElement('canvas');
  canvas.style.cssText = 'position:absolute;left:0;top:0;width:100%;height:100%';
  root.appendChild(canvas);
  doc.body.appendChild(root);
  var ctx = canvas.getContext('2d');
  var trails = doc.createElement('canvas');                         // the streaks: drawn once, faded each frame, wiped by the blade
  var tctx = trails.getContext('2d');
  var sim = CsfxSim.create(1100);
  var st = { on: false, hull: null, p: { spray: 0, frost: 0, rain: 0, wet: 0, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, size: 3, density: 4.5, airGain: 4, fan: 0.8 }, bbox: null, msgs: 0, debug: false };
  var last = null, lastDraw = 0, running = false, lastReport = 0, lastDrawT = 0;
  // The canvases are as big as the screen, but everything drawn lies in the windscreen's bounding box: so that is all that is cleared, faded and composited (three full-screen
  // passes every frame, about 15 million pixels on an ultrawide, were most of this module's cost). drawn: where the last frame drew; trailBox: where the streaks canvas has
  // ever been drawn on since it was last empty (the fade has to reach all of it). Rectangles are { x0, y0, x1, y1 } in pixels.
  var drawn = null, trailBox = null, PAD = 24;
  function join(a, b) { return a ? { x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0), x1: Math.max(a.x1, b.x1), y1: Math.max(a.y1, b.y1) } : b; }
  var px = new Float32Array(sim.n), py = new Float32Array(sim.n), seen = new Uint8Array(sim.n), born = new Float64Array(sim.n);     // where each drop was a frame ago
  var STEP = 1000 / 30;
  var frostTex = CsfxSim.frostTexture(doc, 256);
  var mistTex = (function () {                                       // road spray: a haze and a fine grey-white speckle, made once
    var c = doc.createElement('canvas');
    c.width = c.height = 256;
    var m = c.getContext('2d'), seed = 777;
    function rr() { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; }
    m.fillStyle = 'rgba(205,212,220,0.55)'; m.fillRect(0, 0, 256, 256);
    for (var i = 0; i < 1800; i++) { m.fillStyle = 'rgba(245,248,252,' + (0.4 + rr() * 0.5) + ')'; m.beginPath(); m.arc(rr() * 256, rr() * 256, 0.8 + rr() * 2.0, 0, 6.283); m.fill(); }
    return c;
  })();
  var frostLayer = doc.createElement('canvas');                      // the frost as it is now: the blades clear arcs out of it, which stay clear until the frost is gone
  frostLayer.width = frostLayer.height = 256;
  var fctx = frostLayer.getContext('2d'), frostFresh = false;
  // two blades (tandem): pivots on the bottom edge of the windscreen, sweeping from lying to the left up and over to the right; the angle is measured up from the +x axis
  var BLADES = [{ px: 0.28, len: 0.62 }, { px: 0.74, len: 0.62 }], A_REST = 2.9, A_END = 0.25;
  var ph = 0, phDir = 1, aPrev = A_REST, aNow = A_REST;
  function wedge(c2d, cx, cy, L, a0, a1) {                           // the circle sector between two blade angles, as a filled path
    var lo = Math.min(a0, a1) - 0.02, hi = Math.max(a0, a1) + 0.02;
    c2d.beginPath(); c2d.moveTo(cx, cy); c2d.arc(cx, cy, L, -hi, -lo, false); c2d.closePath(); c2d.fill();
  }

  // one drop as a lens, for a bright scene: a dark film (darker in the top half: the drop shows the darker ground there), a soft light spot low right, a dark edge all
  // round (heavier low right), a bright rim up-left and one glint. (A light film vanishes against a bright sky or concrete: only dark reads there.)
  var S = 64, sprite = doc.createElement('canvas');
  sprite.width = sprite.height = S;
  (function () {
    var c = sprite.getContext('2d'), data = c.createImageData(S, S);
    function over(dst, r, g, b, a) { if (a <= 0) return; var k = 1 - a; dst[0] = r * a + dst[0] * k; dst[1] = g * a + dst[1] * k; dst[2] = b * a + dst[2] * k; dst[3] = a + dst[3] * k; }      // (premultiplied)
    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {
      var u = (x + 0.5) / S * 2 - 1, v = (y + 0.5) / S * 2 - 1, d2 = u * u + v * v, o = (y * S + x) * 4;
      if (d2 >= 1) { data.data[o + 3] = 0; continue; }
      var d = Math.sqrt(d2), fade = Math.min(1, (1 - d) * 8), dir = (u + v) * 0.7071, px = [0, 0, 0, 0];
      var top = Math.max(0, -v), body = 0.1 + (true ? 0.20 * Math.pow(top, 1.3) : 0);
      over(px, 12, 18, 30, body * (d < 0.9 ? 1 : 0.5));                                          // the body: a dark film, darker toward the top
      var cx = u - 0.22, cy = v - 0.4;
      over(px, 255, 255, 255, 0.30 * Math.exp(-(cx * cx + cy * cy) / 0.10) * (d < 0.9 ? 1 : 0));   // light that the drop focuses, low right
      var ring = Math.max(0, 1 - Math.abs(d - 0.86) / 0.14);
      over(px, 10, 14, 24, Math.min(0.9, ring * 0.85 * (0.75 + 0.25 * Math.max(0, dir))));      // the dark edge all round, heavier low right
      var rim = ring * Math.max(0, -dir);
      over(px, 255, 255, 255, Math.min(1, rim * 0.95));                                           // the bright rim up-left
      var gx = u + 0.4, gy = v + 0.45;
      over(px, 255, 255, 255, Math.min(1, 1.6 * Math.exp(-(gx * gx + gy * gy) / 0.022)));       // the glint: big and hard, a wet drop is shiny
      var g2x = u - 0.38, g2y = v - 0.42;
      over(px, 255, 255, 255, Math.min(1, 0.7 * Math.exp(-(g2x * g2x + g2y * g2y) / 0.015)));   // and a smaller second one low right, the light that comes through
      var a = px[3];
      data.data[o] = a > 0 ? Math.round(px[0] / a) : 0; data.data[o + 1] = a > 0 ? Math.round(px[1] / a) : 0; data.data[o + 2] = a > 0 ? Math.round(px[2] / a) : 0;
      data.data[o + 3] = Math.min(255, a * fade * 255);
    }
    c.putImageData(data, 0, 0);
  })();

  // a small bead (under about 8 px): a dark rim all round, a faint dark body, a soft light spot low right and a small glint up left; the big sprite's hard glints turned a small
  // drop into a white dot that read as snow
  var BS = 24, bead = doc.createElement('canvas');
  bead.width = bead.height = BS;
  (function () {
    var c = bead.getContext('2d'), data = c.createImageData(BS, BS);
    for (var y = 0; y < BS; y++) for (var x = 0; x < BS; x++) {
      var u = (x + 0.5) / BS * 2 - 1, v = (y + 0.5) / BS * 2 - 1, d = Math.sqrt(u * u + v * v), o = (y * BS + x) * 4;
      if (d >= 1) { data.data[o + 3] = 0; continue; }
      var rim = Math.max(0, 1 - Math.abs(d - 0.88) / 0.2) * Math.max(0, (u + v) * 0.7071 + 0.15);   // a thin dark lower rim only (the upper side lets the sky through)
      var spot = d < 0.85 ? 0.3 * (1 - (u + v) * 0.35) : 0;           // the body is lighter than the glass: it takes the bright sky
      var gx = u + 0.4, gy = v + 0.45, glint = Math.min(1, 1.2 * Math.exp(-(gx * gx + gy * gy) / 0.01));
      var dark = Math.min(0.9, 0.05 + rim * 0.62), lightA = Math.min(1, spot + glint);
      var a = dark + lightA * (1 - dark);                       // the colour is the share of light in the two
      var k = a > 0 ? lightA / (dark + lightA) : 0, col = Math.round(18 * (1 - k) + 255 * k);
      data.data[o] = data.data[o + 1] = data.data[o + 2] = col; data.data[o + 3] = Math.round(Math.min(1, a) * Math.min(1, (1 - d) * 6) * 255);
    }
    c.putImageData(data, 0, 0);
  })();

  function bbox(h) {
    var x0 = 1, y0 = 1, x1 = 0, y1 = 0;
    for (var i = 0; i < h.length; i += 2) { x0 = Math.min(x0, h[i]); x1 = Math.max(x1, h[i]); y0 = Math.min(y0, h[i + 1]); y1 = Math.max(y1, h[i + 1]); }
    return { x0: x0, y0: y0, w: Math.max(0.01, x1 - x0), h: Math.max(0.01, y1 - y0) };
  }

  function frame(now) {
    if (!st.on) { running = false; root.style.display = 'none'; return; }
    win.requestAnimationFrame(frame);
    if (now - lastDraw < STEP - 1) return;                          // 30 frames a second is plenty for water
    var dt = last === null ? 0.033 : Math.min((now - last) / 1000, 0.1);
    last = now; lastDraw = now;
    var W = win.innerWidth || 1280, H = win.innerHeight || 720;
    if (canvas.width !== W || canvas.height !== H) { canvas.width = W; canvas.height = H; trails.width = W; trails.height = H; drawn = trailBox = null; }
    var cur = null;
    if (st.hull && st.bbox) {
      var bb = st.bbox;
      cur = { x0: Math.max(0, Math.floor(bb.x0 * W - PAD)), y0: Math.max(0, Math.floor(bb.y0 * H - PAD)), x1: Math.min(W, Math.ceil((bb.x0 + bb.w) * W + PAD)), y1: Math.min(H, Math.ceil((bb.y0 + bb.h) * H + PAD)) };
      if (st.debug) cur.x1 = Math.min(W, Math.max(cur.x1, Math.ceil(bb.x0 * W + 460)));          // (the debug text may run past the box)
    }
    var wipe = join(drawn, cur || drawn || { x0: 0, y0: 0, x1: 0, y1: 0 });
    ctx.clearRect(wipe.x0, wipe.y0, wipe.x1 - wipe.x0, wipe.y1 - wipe.y0);
    drawn = cur;
    if (!cur) return;
    trailBox = join(trailBox, cur);
    var wp = st.p.wiper;
    st.p.wiper = 0;                                                   // the blades are the overlay's own (arcs), not the simulation's column
    var rn = st.p.rain;
    if (wp > 0.05) st.p.rain = rn * 0.8;                               // with the wipers going a little less lands between sweeps
    CsfxSim.step(sim, dt, st.p);
    st.p.rain = rn; st.p.wiper = wp;
    var b = st.bbox, bw = b.w * W, bh = b.h * H, bx = b.x0 * W, by = b.y0 * H;
    for (var fi = 0; fi < sim.fresh.length; fi++) born[sim.fresh[fi]] = now;       // drops that just landed get a ring (below)
    sim.fresh.length = 0;

    // the streaks: fade what is there, add a thin wobbling line behind each drop that has moved, wipe the blade's path
    tctx.globalCompositeOperation = 'destination-out';
    tctx.fillStyle = 'rgba(0,0,0,0.04)';
    tctx.fillRect(trailBox.x0, trailBox.y0, trailBox.x1 - trailBox.x0, trailBox.y1 - trailBox.y0);
    tctx.globalCompositeOperation = 'source-over';
    tctx.lineCap = 'round'; tctx.strokeStyle = 'rgba(35,45,60,0.34)'; tctx.lineWidth = 1.3; tctx.beginPath();      // every streak in one path: one stroke a frame, not one per drop
    for (var k = 0; k < sim.n; k++) {
      if (!sim.alive[k]) { seen[k] = 0; continue; }
      var X = bx + sim.x[k] * bw, Y = by + sim.y[k] * bh;
      if (seen[k] && sim.r[k] > 0.012 * st.p.size * 0.6) {
        var dx = X - px[k], dy = Y - py[k];
        if (dx * dx + dy * dy > 0.5 && dx * dx + dy * dy < 900) {
          var w = 1.6, wob = Math.sin(Y * 0.12 + k * 1.7) * w * 0.25;
          tctx.moveTo(px[k] + Math.sin(py[k] * 0.12 + k * 1.7) * w * 0.25, py[k]); tctx.lineTo(X + wob, Y);
        }
      }
      px[k] = X; py[k] = Y; seen[k] = 1;
    }
    tctx.stroke();
    if (st.p.frost < 0.05) frostFresh = false;
    else if (!frostFresh) { fctx.setTransform(1, 0, 0, 1, 0, 0); fctx.globalCompositeOperation = 'source-over'; fctx.clearRect(0, 0, 256, 256); fctx.drawImage(frostTex, 0, 0); frostFresh = true; }
    aPrev = aNow;
    if (st.p.wiper > 0.05) {                                          // the blades sweep a clear arc (the car's own wipers are on): drops in it are gone, the streaks and the frost too
      ph += phDir * dt * st.p.wiper * 0.9;
      if (ph > 1) { ph = 1; phDir = -1; } else if (ph < 0) { ph = 0; phDir = 1; }
      aNow = A_REST + (A_END - A_REST) * ph;
      tctx.globalCompositeOperation = 'destination-out'; tctx.fillStyle = 'rgba(0,0,0,1)';
      fctx.globalCompositeOperation = 'destination-out'; fctx.fillStyle = 'rgba(0,0,0,1)';
      fctx.setTransform(256 / bw, 0, 0, 256 / bh, -bx * 256 / bw, -by * 256 / bh);
      for (var wb = 0; wb < 2; wb++) {
        var cx = bx + (BLADES[wb].px) * bw, cy = by + bh, L = BLADES[wb].len * bw;
        wedge(tctx, cx, cy, L, aPrev, aNow);
        if (st.p.frost > 0.01) wedge(fctx, cx, cy, L, aPrev, aNow);
        var lo = Math.min(aPrev, aNow) - 0.02, hi = Math.max(aPrev, aNow) + 0.02;
        for (var q = 0; q < sim.n; q++) {
          if (!sim.alive[q]) continue;
          var ddx = bx + sim.x[q] * bw - cx, ddy = cy - (by + sim.y[q] * bh);
          if (ddx * ddx + ddy * ddy > L * L) continue;
          var an = Math.atan2(ddy, ddx);
          if (an >= lo && an <= hi) sim.alive[q] = 0;
        }
      }
      tctx.globalCompositeOperation = 'source-over';
      fctx.setTransform(1, 0, 0, 1, 0, 0); fctx.globalCompositeOperation = 'source-over';
    }

    ctx.save();
    ctx.beginPath();
    for (var i = 0; i < st.hull.length; i += 2) {
      if (i === 0) ctx.moveTo(st.hull[i] * W, st.hull[i + 1] * H); else ctx.lineTo(st.hull[i] * W, st.hull[i + 1] * H);
    }
    ctx.closePath();
    ctx.clip();
    if (st.p.frost > 0.01) {                                          // ice under the drops
      ctx.globalAlpha = Math.min(1, st.p.frost * 1.2);
      ctx.drawImage(frostLayer, bx, by, bw, bh);
      ctx.globalAlpha = 1;
    }
    ctx.drawImage(trails, cur.x0, cur.y0, cur.x1 - cur.x0, cur.y1 - cur.y0, cur.x0, cur.y0, cur.x1 - cur.x0, cur.y1 - cur.y0);      // (the clip is inside the box: nothing else shows)
    if (st.p.spray > 0.02) {
      ctx.globalAlpha = Math.min(0.9, st.p.spray * 1.2);
      ctx.drawImage(mistTex, bx, by, bw, bh);
      ctx.globalAlpha = 1;
    }
    var alive = 0;
    for (var n = 0; n < sim.n; n++) {
      if (!sim.alive[n]) continue;
      alive++;
      var R = Math.min(7, Math.max(1.2, Math.pow(sim.r[n] * bh, 1.25) * 0.45));          // real drops seen from the seat: mostly 2 to 8 px across, a few up to 12, flattened
      ctx.drawImage(bead, bx + sim.x[n] * bw - R, by + sim.y[n] * bh - R * 0.85, R * 2, R * 1.7);
      var age = now - born[n];
      if (age >= 0 && age < 320) {                                    // a drop landing: a ring that spreads and fades, a dark one and a light one so it shows on any background
        var k2 = age / 320, rr2 = Math.min(R, 4) * (1.2 + 1.2 * k2), cx2 = bx + sim.x[n] * bw, cy2 = by + sim.y[n] * bh;      // a small ring, not a halo: it is the drop landing, not the drop
        ctx.lineWidth = 1;
        ctx.strokeStyle = 'rgba(255,255,255,' + (0.25 * (1 - k2)).toFixed(2) + ')'; ctx.beginPath(); ctx.arc(cx2, cy2, rr2, 0, 6.2832); ctx.stroke();
      }
    }
    if (st.p.wiper > 0.05) {                                          // the blades themselves: a thin dark rubber line along the sweep angle (the car's own wipers do not move for this view)
      ctx.strokeStyle = 'rgba(20,25,30,0.13)'; ctx.lineWidth = 7; ctx.lineCap = 'round'; ctx.beginPath();
      for (var wl = 0; wl < 2; wl++) { var wcx = bx + BLADES[wl].px * bw, wcy = by + bh, wL = BLADES[wl].len * bw; ctx.moveTo(wcx, wcy); ctx.lineTo(wcx + Math.cos(aNow) * wL, wcy - Math.sin(aNow) * wL); }
      ctx.stroke();
      ctx.strokeStyle = 'rgba(20,25,30,0.28)'; ctx.lineWidth = 1.2; ctx.stroke();      // a soft wet smear with a thin edge line, not a black string
    }
    ctx.restore();
    if (st.debug && now - lastReport > 1000) {                         // tell the game side what the page is doing (carSurfaceFx.overlayReport)
      lastReport = now;
      var fps = Math.round(1000 / Math.max(1, now - lastDrawT)), text = 'drops ' + alive + ' fps~' + fps + ' box ' + Math.round(bx) + ',' + Math.round(by) + ' ' + Math.round(bw) + 'x' + Math.round(bh) + ' of ' + W + 'x' + H +
        ' rain ' + st.p.rain.toFixed(2) + ' speed ' + st.p.speed.toFixed(1) + ' wiper ' + st.p.wiper.toFixed(1) + ' msgs ' + st.msgs;
      try {                                                          // what the layer really is: pixels lit on its canvas, its style, and what lies on top at the middle of the box
        var gd = ctx.getImageData(Math.max(0, Math.round(bx)), Math.max(0, Math.round(by)), Math.max(1, Math.min(W - Math.round(bx), Math.round(bw))), Math.max(1, Math.min(H - Math.round(by), Math.round(bh)))), lit = 0, dd = gd.data;
        for (var li = 3; li < dd.length; li += 32) if (dd[li] > 8) lit++;
        var cs = win.getComputedStyle(root), top = doc.elementFromPoint ? doc.elementFromPoint(bx + bw * 0.5, by + bh * 0.5) : null;
        text += ' | lit ' + lit + ' display ' + cs.display + ' vis ' + cs.visibility + ' op ' + cs.opacity + ' z ' + cs.zIndex + ' inBody ' + (root.parentNode === doc.body) + ' top ' + (top ? top.tagName + '.' + (top.className || '') + '#' + (top.id || '') : 'none') + ' win ' + win.innerWidth + 'x' + win.innerHeight;
      } catch (e) { text += ' | probe failed ' + e; }
      if (win.bngApi && win.bngApi.engineLua) win.bngApi.engineLua('carSurfaceFx.overlayReport(' + JSON.stringify(text) + ')');
    }
    lastDrawT = now;
    if (st.debug) {                                                  // outline of the clip area and a counter: proves the module is loaded and the hull arrives
      ctx.strokeStyle = 'rgba(255,0,0,0.9)'; ctx.lineWidth = 3; ctx.beginPath();
      for (var j = 0; j < st.hull.length; j += 2) { if (j === 0) ctx.moveTo(st.hull[j] * W, st.hull[j + 1] * H); else ctx.lineTo(st.hull[j] * W, st.hull[j + 1] * H); }
      ctx.closePath(); ctx.stroke();
      ctx.fillStyle = 'rgba(255,0,0,0.9)'; ctx.font = '16px sans-serif';
      ctx.fillText('csfx overlay: ' + alive + ' drops, rain ' + st.p.rain.toFixed(2) + ', speed ' + st.p.speed.toFixed(1) + ', wiper ' + st.p.wiper.toFixed(1) + ', msgs ' + st.msgs + ', box ' + Math.round(bw) + 'x' + Math.round(bh), bx + 10, by + 24);
    }
  }

  function handle(name, data) {
    if (!data) return;
    if (!data.on) { st.on = false; sim = CsfxSim.create(1100); seen.fill(0); return; }
    st.msgs++; st.debug = !!data.debug;
    st.hull = data.hull && data.hull.length >= 6 ? data.hull : null;
    st.bbox = st.hull ? bbox(st.hull) : null;
    var p = st.p;
    ['spray', 'frost', 'rain', 'wet', 'speed', 'aLong', 'aLat', 'wiper', 'size'].forEach(function (k) { if (typeof data[k] === 'number' && isFinite(data[k])) p[k] = data[k]; });
    if (!st.on) { st.on = true; last = null; lastDraw = 0; }
    root.style.display = 'block';
    if (!running) { running = true; win.requestAnimationFrame(frame); }
  }

  return { handle: handle, root: root, canvas: canvas, state: st, sim: function () { return sim; } };
}

if (typeof window !== 'undefined') window.__csfxScreenCreate = createOverlay;

if (typeof angular !== 'undefined' && typeof window !== 'undefined' && !window.__csfxScreenTest) {
  angular.module('csfxRain', []).run(['$rootScope', function ($rootScope) {
    if (window.__csfxScreen) return;
    var overlay = createOverlay(document, window);
    window.__csfxScreen = overlay;
    $rootScope.$on('csfxScreen', function (ev, data) { overlay.handle('csfxScreen', data); });
  }]);
}
