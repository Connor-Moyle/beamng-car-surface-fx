// Car Surface FX window canvas: this page IS the glass's base colour map while it is wet. It draws the glass's own tint image first (the game side puts its path in the
// URL as ?base=...) and the water drops on top as light glints and dark edges. The game side sends csfxSet({...}) a few times a second; this page runs the drops
// (sim.js) and draws every frame.
(function () {
  var canvas = document.getElementById('csfx');
  var W = canvas.width = window.innerWidth || 512, H = canvas.height = window.innerHeight || 512;
  var ctx = canvas.getContext('2d');
  var sim = CsfxSim.create();
  var p = { rain: 0, wet: 0, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1 };
  var last = performance.now();

  // the background: the glass's tint image, darkened to the engine's linear reading of a canvas (a plain sRGB value would come out washed out): drawing the
  // canvas over itself with 'multiply' squares every value, close to the 2.2 power. Until the image has loaded (or when it cannot) a dark grey tint stands in.
  var bg = document.createElement('canvas');
  bg.width = W; bg.height = H;
  var bctx = bg.getContext('2d');
  bctx.fillStyle = 'rgb(20,20,20)'; bctx.fillRect(0, 0, W, H);
  var m = /[?&]base=([^&]+)/.exec(location.search);
  if (m) {
    var img = new Image();
    img.onload = function () {
      bctx.globalCompositeOperation = 'source-over';
      bctx.drawImage(img, 0, 0, W, H);
      bctx.globalCompositeOperation = 'multiply';
      bctx.drawImage(bg, 0, 0);
      bctx.globalCompositeOperation = 'source-over';
    };
    img.src = 'local://local/' + decodeURIComponent(m[1]).replace(/^\//, '');
  }

  // one drop as a shading sprite: white (glint) or black (shade) with the strength as alpha, so over the tint it lightens or darkens
  var S = 64, sprite = document.createElement('canvas');
  sprite.width = sprite.height = S;
  (function () {
    var c = sprite.getContext('2d'), data = c.createImageData(S, S);
    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {
      var u = (x + 0.5) / S * 2 - 1, v = (y + 0.5) / S * 2 - 1, d2 = u * u + v * v, o = (y * S + x) * 4;
      if (d2 >= 1) { data.data[o + 3] = 0; continue; }
      var d = Math.sqrt(d2);
      var hx = u + 0.35, hy = v + 0.4;
      var s = 0.12 + 0.9 * Math.exp(-(hx * hx + hy * hy) / 0.06);                    // a lit body and a sharp glint up-left
      var rim = Math.max(0, (d - 0.62) / 0.38);
      s -= rim * rim * (0.35 + 0.45 * Math.max(0, (u + v) * 0.5));                   // the edge shades, most at the bottom right
      var fade = Math.min(1, (1 - d) * 6);
      var level = s >= 0 ? 255 : 0;
      data.data[o] = data.data[o + 1] = data.data[o + 2] = level;
      data.data[o + 3] = Math.min(255, Math.abs(s) * 255 * fade);
    }
    c.putImageData(data, 0, 0);
  })();

  window.csfxSet = function (q) { for (var k in q) p[k] = q[k]; };
  window.csfxClear = function () { sim = CsfxSim.create(); };

  function frame(now) {
    var dt = Math.min((now - last) / 1000, 0.1); last = now;
    CsfxSim.step(sim, dt, p);
    ctx.globalCompositeOperation = 'source-over';
    ctx.drawImage(bg, 0, 0);
    for (var i = 0; i < sim.n; i++) {
      if (!sim.alive[i]) continue;
      var R = sim.r[i] * H;
      ctx.drawImage(sprite, sim.x[i] * W - R, sim.y[i] * H - R, R * 2, R * 2);
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
