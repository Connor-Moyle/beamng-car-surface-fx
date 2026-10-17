// Car Surface FX: the water on a window, as pure functions (no DOM), so node can test them (tests/simtest.js). The page (glass.html) draws the result.
// Units: x, y and r are fractions of the canvas; the canvas is the window material's UV space. (gx, gy) is the unit vector that points DOWN the glass in that space.
(function (root) {
  var MAX = 260;

  function create() {
    return { n: MAX, x: new Float32Array(MAX), y: new Float32Array(MAX), r: new Float32Array(MAX), alive: new Uint8Array(MAX), t: 0, wipe: 0, wipeDir: 1, seed: 12345 };
  }
  function rnd(d) { d.seed = (d.seed * 16807) % 2147483647; return d.seed / 2147483647; }

  function freeSlot(d) { for (var i = 0; i < d.n; i++) if (!d.alive[i]) return i; return -1; }

  // add a drop; one that lands on another merges into it (areas add, the centre moves toward the bigger one)
  function add(d, x, y, r) {
    for (var i = 0; i < d.n; i++) {
      if (!d.alive[i]) continue;
      var dx = d.x[i] - x, dy = d.y[i] - y, rr = d.r[i] + r;
      if (dx * dx + dy * dy < rr * rr * 0.6) {
        var nr = Math.sqrt(d.r[i] * d.r[i] + r * r), w = d.r[i] / (d.r[i] + r);
        d.x[i] = d.x[i] * w + x * (1 - w); d.y[i] = d.y[i] * w + y * (1 - w); d.r[i] = nr;
        return i;
      }
    }
    var s = freeSlot(d);
    if (s < 0) return -1;
    d.x[s] = x; d.y[s] = y; d.r[s] = r; d.alive[s] = 1;
    return s;
  }

  function count(d) { var n = 0; for (var i = 0; i < d.n; i++) n += d.alive[i]; return n; }

  var SLIDE = 0.012;       // a drop bigger than this runs down the glass

  // p: { rain 0..1 (falling now), wet 0..1 (how wet the glass is), speed m/s, aLong, aLat (m/s^2, braking < 0, right > 0), wiper 0..1, gx, gy,
  //       size: drop size and density scale (a window uses only part of the texture, so the drops must be bigger than the numbers below say; default 1) }
  function step(d, dt, p) {
    d.t += dt;
    var gx = p.gx, gy = p.gy, px = -gy, py = gx;                      // px,py: across the glass
    var z = p.size || 1, slide = SLIDE * z;
    var cap = Math.floor((60 + 240 * p.rain) / z);                      // how many drops a window carries at most: more rain, more drops (bigger drops, fewer)
    var n0 = count(d);
    var spawns = n0 < cap ? p.rain * 80 * z * (0.5 + Math.min(p.speed / 30, 1)) * dt : 0;
    while (spawns > 0) {
      if (spawns >= 1 || rnd(d) < spawns) { var q = rnd(d); add(d, rnd(d), rnd(d), (0.006 + 0.012 * q * q) * z); }
      spawns -= 1;
    }
    // where the air and the car's motion push: down the glass at rest, back up it with speed, braking throws it forward and down, accelerating back
    var down = 0.02 - Math.pow(p.speed / 30, 2) * 0.35 - p.aLong * 0.012;
    var across = p.aLat * 0.012;
    var evap = (1 - Math.min(p.rain * 3, 1)) * dt * (0.0015 + 0.004 * (1 - p.wet));
    for (var i = 0; i < d.n; i++) {
      if (!d.alive[i]) continue;
      var r = d.r[i];
      var big = r > slide ? (r / slide) : 0;                          // big drops move on their own, small ones only when the air pushes hard
      var air = p.speed > 6 ? Math.min((p.speed - 6) / 20, 1) : 0;
      var f = Math.max(big, air);
      var vd = down * f, va = across * f;
      if (r > slide && down > 0) vd += 0.03 * big * big;             // the weight of a big drop
      var nx = d.x[i] + (gx * vd + px * va) * dt, ny = d.y[i] + (gy * vd + py * va) * dt;
      if (r > slide) {                                                // a running drop leaves small drops behind
        var moved = Math.abs(nx - d.x[i]) + Math.abs(ny - d.y[i]);
        if (n0 < cap && moved > 0 && rnd(d) < moved * 60) add(d, d.x[i] - gx * r * 1.6, d.y[i] - gy * r * 1.6, (0.0025 + 0.002 * rnd(d)) * z);
      }
      d.x[i] = nx; d.y[i] = ny;
      d.r[i] -= evap;
      if (d.r[i] < 0.0022 * z || d.x[i] < -0.05 || d.x[i] > 1.05 || d.y[i] < -0.05 || d.y[i] > 1.05) d.alive[i] = 0;
    }
    if (p.wiper > 0.05) {                                             // the blade sweeps across the glass (along px,py) and wipes what it crosses
      var prev = d.wipe;
      d.wipe += d.wipeDir * dt * p.wiper * 0.9;
      if (d.wipe > 1) { d.wipe = 1; d.wipeDir = -1; } else if (d.wipe < 0) { d.wipe = 0; d.wipeDir = 1; }
      var lo = Math.min(prev, d.wipe) - 0.03, hi = Math.max(prev, d.wipe) + 0.03;
      for (var j = 0; j < d.n; j++) {
        if (!d.alive[j]) continue;
        var c = d.x[j] * px + d.y[j] * py;                            // position across the glass, 0..1 when (px,py) is an axis
        if (px + py < 0) c = 1 + c;
        if (c >= lo && c <= hi) d.alive[j] = 0;
      }
    }
  }

  var api = { create: create, step: step, add: add, count: count, MAX: MAX, SLIDE: SLIDE };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.CsfxSim = api;
})(this);
