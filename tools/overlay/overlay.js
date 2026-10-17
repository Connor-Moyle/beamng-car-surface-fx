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
  var sim = CsfxSim.create();
  var st = { on: false, hull: null, p: { spray: 0, frost: 0, rain: 0, wet: 0, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, size: 3 }, bbox: null, msgs: 0, debug: false };
  var last = null, lastDraw = 0, running = false;
  var px = new Float32Array(sim.n), py = new Float32Array(sim.n), seen = new Uint8Array(sim.n);     // where each drop was a frame ago
  var STEP = 1000 / 30;
  var frostTex = CsfxSim.frostTexture(doc, 256);
  var mistTex = (function () {                                       // road spray: a haze and a fine grey-white speckle, made once
    var c = doc.createElement('canvas');
    c.width = c.height = 256;
    var m = c.getContext('2d'), seed = 777;
    function rr() { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; }
    m.fillStyle = 'rgba(200,208,216,0.35)'; m.fillRect(0, 0, 256, 256);
    for (var i = 0; i < 1800; i++) { m.fillStyle = 'rgba(235,240,246,' + (0.25 + rr() * 0.5) + ')'; m.beginPath(); m.arc(rr() * 256, rr() * 256, 0.6 + rr() * 1.4, 0, 6.283); m.fill(); }
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

  // one drop as a lens: a faint light film, darker toward the centre, a lighter rim up-left, a dark crescent down-right, one glint
  var S = 64, sprite = doc.createElement('canvas');
  sprite.width = sprite.height = S;
  (function () {
    var c = sprite.getContext('2d'), data = c.createImageData(S, S);
    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {
      var u = (x + 0.5) / S * 2 - 1, v = (y + 0.5) / S * 2 - 1, d2 = u * u + v * v, o = (y * S + x) * 4;
      if (d2 >= 1) { data.data[o + 3] = 0; continue; }
      var d = Math.sqrt(d2), fade = Math.min(1, (1 - d) * 8);
      var ring = Math.max(0, 1 - Math.abs(d - 0.84) / 0.16), dir = (u + v) * 0.7071;
      var s = ring * (dir > 0 ? -0.9 * dir : 0.7 * -dir);
      var gx = u + 0.4, gy = v + 0.45;
      s += 0.95 * Math.exp(-(gx * gx + gy * gy) / 0.012);
      var r = 205, g = 222, b = 240, a = 0.18 + 0.10 * d;                              // the film: a little lighter toward the edge (the middle looks through)
      a += 0.14 * (1 - d) * (dir > 0 ? 1 : 0.4);                                       // and a darker core down-right: the lens turns the picture
      if (s > 0.15) { r = g = b = 255; a = Math.min(1, s); }                          // glint and bright rim
      else if (s < -0.05) { r = g = b = 0; a = Math.min(0.85, -s * 1.3); }            // the dark crescent
      else if (d < 0.6) { r = g = b = 20; a = 0.14 * (1 - d); }                        // dark core
      data.data[o] = r; data.data[o + 1] = g; data.data[o + 2] = b;
      data.data[o + 3] = Math.min(255, a * fade * 255);
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
    if (canvas.width !== W || canvas.height !== H) { canvas.width = W; canvas.height = H; trails.width = W; trails.height = H; }
    ctx.clearRect(0, 0, W, H);
    if (!st.hull || !st.bbox) return;
    var wp = st.p.wiper;
    st.p.wiper = 0;                                                   // the blades are the overlay's own (arcs), not the simulation's column
    CsfxSim.step(sim, dt, st.p);
    st.p.wiper = wp;
    var b = st.bbox, bw = b.w * W, bh = b.h * H, bx = b.x0 * W, by = b.y0 * H;

    // the streaks: fade what is there, add a thin wobbling line behind each drop that has moved, wipe the blade's path
    tctx.globalCompositeOperation = 'destination-out';
    tctx.fillStyle = 'rgba(0,0,0,0.035)';
    tctx.fillRect(0, 0, W, H);
    tctx.globalCompositeOperation = 'source-over';
    tctx.lineCap = 'round';
    for (var k = 0; k < sim.n; k++) {
      if (!sim.alive[k]) { seen[k] = 0; continue; }
      var X = bx + sim.x[k] * bw, Y = by + sim.y[k] * bh;
      if (seen[k] && sim.r[k] > 0.012 * st.p.size * 0.6) {
        var dx = X - px[k], dy = Y - py[k];
        if (dx * dx + dy * dy > 0.5 && dx * dx + dy * dy < 40000) {
          var w = Math.max(1, sim.r[k] * bh * 0.3), wob = Math.sin(Y * 0.12 + k * 1.7) * w * 0.9;
          tctx.strokeStyle = 'rgba(215,230,245,0.34)';
          tctx.lineWidth = w;
          tctx.beginPath(); tctx.moveTo(px[k] + Math.sin(py[k] * 0.12 + k * 1.7) * w * 0.9, py[k]); tctx.lineTo(X + wob, Y); tctx.stroke();
        }
      }
      px[k] = X; py[k] = Y; seen[k] = 1;
    }
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
    ctx.drawImage(trails, 0, 0);
    if (st.p.spray > 0.02) {
      ctx.globalAlpha = Math.min(0.7, st.p.spray * 0.9);
      ctx.drawImage(mistTex, bx, by, bw, bh);
      ctx.globalAlpha = 1;
    }
    var alive = 0;
    for (var n = 0; n < sim.n; n++) {
      if (!sim.alive[n]) continue;
      alive++;
      var R = Math.max(1.5, sim.r[n] * bh);
      ctx.drawImage(sprite, bx + sim.x[n] * bw - R, by + sim.y[n] * bh - R, R * 2, R * 2);
    }
    ctx.restore();
    if (st.debug) {                                                  // outline of the clip area and a counter: proves the module is loaded and the hull arrives
      ctx.strokeStyle = 'rgba(255,0,0,0.9)'; ctx.lineWidth = 3; ctx.beginPath();
      for (var j = 0; j < st.hull.length; j += 2) { if (j === 0) ctx.moveTo(st.hull[j] * W, st.hull[j + 1] * H); else ctx.lineTo(st.hull[j] * W, st.hull[j + 1] * H); }
      ctx.closePath(); ctx.stroke();
      ctx.fillStyle = 'rgba(255,0,0,0.9)'; ctx.font = '16px sans-serif';
      ctx.fillText('csfx overlay: ' + alive + ' drops, rain ' + st.p.rain.toFixed(2) + ', msgs ' + st.msgs, bx + 10, by + 24);
    }
  }

  function handle(name, data) {
    if (!data) return;
    if (!data.on) { st.on = false; sim = CsfxSim.create(); seen.fill(0); return; }
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
