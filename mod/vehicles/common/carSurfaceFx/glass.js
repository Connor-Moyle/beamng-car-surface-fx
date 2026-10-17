// Car Surface FX window canvas: draws the water on the glass as a tangent-space normal map (flat = rgb 128,128,255) that the game's glass material
// uses as its detail normal map. The game side sends csfxSet({...}) a few times a second; this page runs the drops (sim.js) and draws every frame.
(function () {
  var canvas = document.getElementById('csfx');
  var W = canvas.width = window.innerWidth || 1024, H = canvas.height = window.innerHeight || 1024;
  var ctx = canvas.getContext('2d');
  var sim = CsfxSim.create();
  var p = { rain: 0, wet: 0, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1 };
  var last = performance.now();

  // one bead as a normal map sprite: a round cap, tangent-space normal pointing away from the centre, flat outside
  var S = 64, sprite = document.createElement('canvas');
  sprite.width = sprite.height = S;
  (function () {
    var c = sprite.getContext('2d'), img = c.createImageData(S, S);
    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {
      var u = (x + 0.5) / S * 2 - 1, v = (y + 0.5) / S * 2 - 1, d2 = u * u + v * v, o = (y * S + x) * 4;
      if (d2 >= 1) { img.data[o + 3] = 0; continue; }
      var z = Math.sqrt(1 - d2), k = 0.9;                                  // sphere normal, eased toward flat so beads read as water, not balls
      var nx = u * k, ny = v * k, nz = Math.max(z, 0.25), l = Math.sqrt(nx * nx + ny * ny + nz * nz);
      img.data[o] = (nx / l * 0.5 + 0.5) * 255; img.data[o + 1] = (ny / l * 0.5 + 0.5) * 255; img.data[o + 2] = (nz / l * 0.5 + 0.5) * 255;
      img.data[o + 3] = Math.min(255, (1 - d2) * 600);
    }
    c.putImageData(img, 0, 0);
  })();

  window.csfxSet = function (q) { for (var k in q) p[k] = q[k]; };
  window.csfxClear = function () { sim = CsfxSim.create(); };

  function frame(now) {
    var dt = Math.min((now - last) / 1000, 0.1); last = now;
    CsfxSim.step(sim, dt, p);
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = 'rgb(128,128,255)';
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
