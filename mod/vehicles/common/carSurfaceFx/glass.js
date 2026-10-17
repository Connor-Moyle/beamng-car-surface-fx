// Car Surface FX window canvas: draws the water on the glass as light and dark shading around a neutral grey (rgb n,n,n, n = 128 unless the game side says otherwise).
// The game's glass material uses the canvas as its base colour DETAIL map, which adds (value*2-1)*strength to the glass colour, so grey changes nothing, light
// spots add light (the glint on a drop) and dark spots take it away (the drop's shaded edge). The game side sends csfxSet({...}) a few times a second;
// this page runs the drops (sim.js) and draws every frame.
(function () {
  var canvas = document.getElementById('csfx');
  var W = canvas.width = window.innerWidth || 1024, H = canvas.height = window.innerHeight || 1024;
  var ctx = canvas.getContext('2d');
  var sim = CsfxSim.create();
  var p = { rain: 0, wet: 0, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, neutral: 128 };
  var last = performance.now();

  // one drop as a shading sprite: white (glint) or black (shade) with the strength as alpha, so on the grey it lightens or darkens
  var S = 64, sprite = document.createElement('canvas');
  sprite.width = sprite.height = S;
  (function () {
    var c = sprite.getContext('2d'), img = c.createImageData(S, S);
    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {
      var u = (x + 0.5) / S * 2 - 1, v = (y + 0.5) / S * 2 - 1, d2 = u * u + v * v, o = (y * S + x) * 4;
      if (d2 >= 1) { img.data[o + 3] = 0; continue; }
      var d = Math.sqrt(d2);
      var hx = u + 0.35, hy = v + 0.4;
      var s = 0.12 + 0.9 * Math.exp(-(hx * hx + hy * hy) / 0.06);                    // a lit body and a sharp glint up-left
      var rim = Math.max(0, (d - 0.62) / 0.38);
      s -= rim * rim * (0.35 + 0.45 * Math.max(0, (u + v) * 0.5));                   // the edge shades, most at the bottom right
      var fade = Math.min(1, (1 - d) * 6);
      var level = s >= 0 ? 255 : 0;
      img.data[o] = img.data[o + 1] = img.data[o + 2] = level;
      img.data[o + 3] = Math.min(255, Math.abs(s) * 255 * fade);
    }
    c.putImageData(img, 0, 0);
  })();

  window.csfxSet = function (q) { for (var k in q) p[k] = q[k]; };
  window.csfxClear = function () { sim = CsfxSim.create(); };

  function frame(now) {
    var dt = Math.min((now - last) / 1000, 0.1); last = now;
    CsfxSim.step(sim, dt, p);
    var n = Math.max(0, Math.min(255, Math.round(p.neutral)));
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = 'rgb(' + n + ',' + n + ',' + n + ')';
    ctx.fillRect(0, 0, W, H);
    for (var i = 0; i < sim.n; i++) {
      if (!sim.alive[i]) continue;
      var R = sim.r[i] * H;
      ctx.drawImage(sprite, sim.x[i] * W - R, sim.y[i] * H - R, R * 2, R * 2);
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
