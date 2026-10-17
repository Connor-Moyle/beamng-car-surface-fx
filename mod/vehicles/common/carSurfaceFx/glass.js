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
  var sim = CsfxSim.create();
  var p = { frost: 0, rain: 0, wet: 0, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, tint: 1, passes: 1, flood: 0 };
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

  // one drop as a sprite: white (glint) or black (shade), the strength as alpha, so over the tint it lightens or darkens: a clear body, a thin bright rim up-left, a dark
  // crescent down-right and one sharp glint. The emissive canvas keeps only the light parts.
  var S = 64, sprite = document.createElement('canvas');
  sprite.width = sprite.height = S;
  (function () {
    var c = sprite.getContext('2d'), data = c.createImageData(S, S);
    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {
      var u = (x + 0.5) / S * 2 - 1, v = (y + 0.5) / S * 2 - 1, d2 = u * u + v * v, o = (y * S + x) * 4;
      if (d2 >= 1) { data.data[o + 3] = 0; continue; }
      var d = Math.sqrt(d2), fade = Math.min(1, (1 - d) * 8);
      var ring = Math.max(0, 1 - Math.abs(d - 0.86) / 0.14);                      // a thin ring near the edge
      var dir = (u + v) * 0.7071;                                                  // + toward the bottom right
      var s = ring * (dir > 0 ? -0.32 * dir : 0.6 * -dir);                         // dark on the lower right of the rim, bright on the upper left
      var gx = u + 0.4, gy = v + 0.45;
      s += 0.95 * Math.exp(-(gx * gx + gy * gy) / 0.012);                          // the glint
      s -= 0.06 * Math.max(0, dir) * (1 - ring);                                    // a slight shade inside, lower right
      if (emissive) s = Math.max(0, s - 0.12 + 0.06 * (1 - Math.min(1, d * 1.5)));      // light only, and no lit body: just the bright rim up-left and the glint (a lit body made the whole glass hazy)
      data.data[o] = data.data[o + 1] = data.data[o + 2] = s >= 0 ? 255 : 0;
      data.data[o + 3] = Math.min(255, Math.min(1, Math.abs(s)) * fade * 255);
    }
    c.putImageData(data, 0, 0);
  })();

  var frostTex = CsfxSim.frostTexture(document, 256);

  window.csfxSet = function (o) { for (var k in o) p[k] = o[k]; if (p.passes !== builtPasses) buildBg(); };
  window.csfxClear = function () { sim = CsfxSim.create(); };

  function frame(now) {
    var dt = Math.min((now - last) / 1000, 0.1); last = now;
    CsfxSim.step(sim, dt, p);
    ctx.globalCompositeOperation = 'source-over';
    ctx.drawImage(bg, 0, 0);
    if (p.flood > 0) { ctx.fillStyle = emissive ? 'rgb(255,255,255)' : 'rgb(255,0,0)'; ctx.fillRect(0, 0, W, H); }      // debug: the whole map solid, to see which surface uses it
    if (!emissive && p.tint < 1) { ctx.fillStyle = 'rgba(0,0,0,' + (1 - p.tint) + ')'; ctx.fillRect(0, 0, W, H); }
    for (var i = 0; i < sim.n; i++) {
      if (!sim.alive[i]) continue;
      var R = sim.r[i] * H;
      ctx.drawImage(sprite, sim.x[i] * W - R, sim.y[i] * H - R, R * 2, R * 2);
    }
    if (p.frost > 0.01) {                                             // ice over the drops
      ctx.globalAlpha = Math.min(1, p.frost * 1.2) * (emissive ? 0.7 : 1);
      ctx.drawImage(frostTex, 0, 0, W, H);
      ctx.globalAlpha = 1;
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
