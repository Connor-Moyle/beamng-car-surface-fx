// Car Surface FX window canvas: this page IS one of the glass material's maps while the glass is wet. The game side puts in the URL which map it is and the original image:
//   ?mode=color&base=<path>    the base colour map: the glass's tint image first, the drops on top as light glints and dark edges
//   ?mode=opacity&base=<path>  the opacity map (used for the inside glass, which is clear: colour changes on it are invisible): the original opacity image, the drops on top
//                              as more opaque water
// The game side sends csfxSet({...}) a few times a second; this page runs the drops (sim.js) and draws every frame.
//   csfxSet({ tint: 0.6 })  darkens the colour map (if the glass looks milky), csfxSet({ passes: 2 }) = how often the image is squared to match the engine's linear reading.
(function () {
  var canvas = document.getElementById('csfx');
  var W = canvas.width = window.innerWidth || 512, H = canvas.height = window.innerHeight || 512;
  var ctx = canvas.getContext('2d');
  var sim = CsfxSim.create();
  var p = { rain: 0, wet: 0, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, tint: 1, passes: 1 };
  var last = performance.now();
  var q = function (name) { var m = new RegExp('[?&]' + name + '=([^&]*)').exec(location.search); return m ? decodeURIComponent(m[1]) : ''; };
  var opacity = q('mode') === 'opacity', basePath = q('base');

  // the background: the original image. A colour map is squared 'passes' times (drawing the canvas over itself with 'multiply') because the engine reads a canvas as linear
  // colour where a png would be decoded from sRGB; a data map (opacity) is used as it is. Until the image has loaded, a dark tint / clear opacity stands in.
  var bg = document.createElement('canvas');
  bg.width = W; bg.height = H;
  var bctx = bg.getContext('2d');
  var img = null, builtPasses = -1;
  function buildBg() {
    builtPasses = p.passes;
    bctx.globalCompositeOperation = 'source-over';
    bctx.fillStyle = opacity ? 'rgb(0,0,0)' : 'rgb(20,20,20)';
    bctx.fillRect(0, 0, W, H);
    if (!img || !img.complete || !img.naturalWidth) return;
    bctx.drawImage(img, 0, 0, W, H);
    if (!opacity) {
      bctx.globalCompositeOperation = 'multiply';
      for (var i = 0; i < p.passes; i++) bctx.drawImage(bg, 0, 0);
      bctx.globalCompositeOperation = 'source-over';
    }
  }
  buildBg();
  if (basePath) {
    img = new Image();
    img.onload = buildBg;
    img.src = 'local://local/' + basePath.replace(/^\//, '');
  }

  // one drop as a sprite. colour mode: white (glint) or black (shade), the strength as alpha, so over the tint it lightens or darkens: a clear body, a thin bright
  // rim up-left, a dark crescent down-right and one sharp glint. opacity mode: white, a faint body and a firmer rim.
  var S = 64, sprite = document.createElement('canvas');
  sprite.width = sprite.height = S;
  (function () {
    var c = sprite.getContext('2d'), data = c.createImageData(S, S);
    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {
      var u = (x + 0.5) / S * 2 - 1, v = (y + 0.5) / S * 2 - 1, d2 = u * u + v * v, o = (y * S + x) * 4;
      if (d2 >= 1) { data.data[o + 3] = 0; continue; }
      var d = Math.sqrt(d2), fade = Math.min(1, (1 - d) * 8);
      var s, level, a;
      if (opacity) {
        level = 255; a = (0.18 + 0.5 * Math.max(0, (d - 0.7) / 0.3)) * fade;
      } else {
        var ring = Math.max(0, 1 - Math.abs(d - 0.86) / 0.14);                      // a thin ring near the edge
        var dir = (u + v) * 0.7071;                                                  // + toward the bottom right
        s = ring * (dir > 0 ? -0.55 * dir : 0.8 * -dir);                             // dark on the lower right of the rim, bright on the upper left
        var gx = u + 0.4, gy = v + 0.45;
        s += 0.95 * Math.exp(-(gx * gx + gy * gy) / 0.012);                          // the glint
        s -= 0.1 * Math.max(0, dir) * (1 - ring);                                    // a slight shade inside, lower right
        level = s >= 0 ? 255 : 0; a = Math.min(1, Math.abs(s)) * fade;
      }
      data.data[o] = data.data[o + 1] = data.data[o + 2] = level;
      data.data[o + 3] = Math.min(255, a * 255);
    }
    c.putImageData(data, 0, 0);
  })();

  window.csfxSet = function (o) { for (var k in o) p[k] = o[k]; if (p.passes !== builtPasses) buildBg(); };
  window.csfxClear = function () { sim = CsfxSim.create(); };

  function frame(now) {
    var dt = Math.min((now - last) / 1000, 0.1); last = now;
    CsfxSim.step(sim, dt, p);
    ctx.globalCompositeOperation = 'source-over';
    ctx.drawImage(bg, 0, 0);
    if (!opacity && p.tint < 1) { ctx.fillStyle = 'rgba(0,0,0,' + (1 - p.tint) + ')'; ctx.fillRect(0, 0, W, H); }
    for (var i = 0; i < sim.n; i++) {
      if (!sim.alive[i]) continue;
      var R = sim.r[i] * H;
      ctx.drawImage(sprite, sim.x[i] * W - R, sim.y[i] * H - R, R * 2, R * 2);
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
