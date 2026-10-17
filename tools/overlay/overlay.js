// The part of the windscreen rain overlay that is not the drop simulation (sim.js is put in front of it by tools/build_overlay.js into
// mod/ui/modModules/csfxRain/csfxRain.js). A global UI module of the game's web UI (the layer the Street Legal HUD uses): a transparent full-screen canvas that never takes
// the mouse; the game side (carSurfaceFx/screen.lua + carSurfaceFx.lua) sends 'csfxScreen' about 15 times a second while the driver's camera looks through a wet
// windscreen: { on, hull: [x1, y1, ...] (screen fractions), rain, wet, speed, aLong, aLat, wiper, size }. The drops are the window simulation, laid into the hull's bounding box and
// clipped to the hull.

function createOverlay(doc, win) {
  var root = doc.createElement('div');
  root.style.cssText = 'position:fixed;left:0;top:0;right:0;bottom:0;pointer-events:none;z-index:35;display:none';
  var canvas = doc.createElement('canvas');
  canvas.style.cssText = 'position:absolute;left:0;top:0;width:100%;height:100%';
  root.appendChild(canvas);
  doc.body.appendChild(root);
  var ctx = canvas.getContext('2d');
  var sim = CsfxSim.create();
  var st = { on: false, hull: null, p: { rain: 0, wet: 0, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, size: 2.2 }, bbox: null };
  var last = null, running = false;

  // one drop as a shading sprite: a faint light body, a bright rim up-left, a dark crescent down-right, one glint (white / black with the strength as alpha)
  var S = 64, sprite = doc.createElement('canvas');
  sprite.width = sprite.height = S;
  (function () {
    var c = sprite.getContext('2d'), data = c.createImageData(S, S);
    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {
      var u = (x + 0.5) / S * 2 - 1, v = (y + 0.5) / S * 2 - 1, d2 = u * u + v * v, o = (y * S + x) * 4;
      if (d2 >= 1) { data.data[o + 3] = 0; continue; }
      var d = Math.sqrt(d2), fade = Math.min(1, (1 - d) * 8);
      var ring = Math.max(0, 1 - Math.abs(d - 0.86) / 0.14), dir = (u + v) * 0.7071;
      var s = ring * (dir > 0 ? -0.9 * dir : 0.7 * -dir);
      var gx = u + 0.4, gy = v + 0.45;
      s += 0.95 * Math.exp(-(gx * gx + gy * gy) / 0.012);
      var r = 205, g = 222, b = 240, a = 0.16 + 0.1 * (1 - d);                         // the body: a faint light-blue film (water bends the light behind it)
      if (s > 0.15) { r = g = b = 255; a = Math.min(1, s); }                          // glint and bright rim
      else if (s < -0.05) { r = g = b = 0; a = Math.min(0.85, -s * 1.3); }            // the dark crescent
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
    var dt = last === null ? 0.016 : Math.min((now - last) / 1000, 0.1);
    last = now;
    var W = win.innerWidth || 1280, H = win.innerHeight || 720;
    if (canvas.width !== W || canvas.height !== H) { canvas.width = W; canvas.height = H; }
    ctx.clearRect(0, 0, W, H);
    if (!st.hull || !st.bbox) return;
    CsfxSim.step(sim, dt, st.p);
    ctx.save();
    ctx.beginPath();
    for (var i = 0; i < st.hull.length; i += 2) {
      if (i === 0) ctx.moveTo(st.hull[i] * W, st.hull[i + 1] * H); else ctx.lineTo(st.hull[i] * W, st.hull[i + 1] * H);
    }
    ctx.closePath();
    ctx.clip();
    var b = st.bbox, bw = b.w * W, bh = b.h * H, bx = b.x0 * W, by = b.y0 * H;
    for (var k = 0; k < sim.n; k++) {
      if (!sim.alive[k]) continue;
      var R = Math.max(1.5, sim.r[k] * bh);
      ctx.drawImage(sprite, bx + sim.x[k] * bw - R, by + sim.y[k] * bh - R, R * 2, R * 2);
    }
    ctx.restore();
  }

  function handle(name, data) {
    if (!data) return;
    if (!data.on) { st.on = false; sim = CsfxSim.create(); return; }
    st.hull = data.hull && data.hull.length >= 6 ? data.hull : null;
    st.bbox = st.hull ? bbox(st.hull) : null;
    var p = st.p;
    ['rain', 'wet', 'speed', 'aLong', 'aLat', 'wiper', 'size'].forEach(function (k) { if (typeof data[k] === 'number' && isFinite(data[k])) p[k] = data[k]; });
    if (!st.on) { st.on = true; last = null; }
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
