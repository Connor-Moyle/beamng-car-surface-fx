// Car Surface FX: water drops running over the car's paint, as pure functions (no DOM), tested by tests/paintwater_test.js. The scratch page (scratch.js) draws them.
// The drops live in the paint texture's UV space (the page's 0..1 x, y). To know which way "down the panel" is at a place, the game side sends a table of body nodes:
// per node its position on the texture (x, y) and how a direction in the car's own coordinates changes it ((jux, juy, juz) = d x per unit step, (jvx, jvy, jvz) = d y per unit
// step) and s = texture units per metre there. A drop looks up the nearest node, turns the force on the water (gravity, the car's acceleration, the wind of driving, all as
// one vector in the car's coordinates, in m/s^2) into a direction on the texture, and runs that way if the pull along the panel beats what holds a drop of its size.
(function (root) {
  var MAXD = 500, CELLS = 32, REACH = 0.07;                                           // a body node this close to a drop tells which way is down there (the nodes are sparse: a door has few)
  var RMAX_M = 0.006;                                     // metres: a drop that has merged this big (6 mm radius) stays a drop: on a flat panel they must not grow into a puddle
  // Every size here is in metres and meets the texture through s, the texture units per metre at the drop's place (the node map gives it), so a drop is the same real size on every car.

  function create() {
    return { n: MAXD, x: new Float32Array(MAXD), y: new Float32Array(MAXD), r: new Float32Array(MAXD), alive: new Uint8Array(MAXD), moved: new Uint8Array(MAXD), age: new Float32Array(MAXD), life: new Float32Array(MAXD), nodes: null, grid: null, seed: 4321, count: 0 };
  }
  function rnd(w) { w.seed = (w.seed * 16807) % 2147483647; return w.seed / 2147483647; }

  // rows: [x, y, jux, juy, juz, jvx, jvy, jvz, s] per node, flat
  function setNodes(w, rows) {
    var n = Math.floor(rows.length / 9), grid = [];
    for (var i = 0; i < CELLS * CELLS; i++) grid.push([]);
    for (var k = 0; k < n; k++) {
      var cx = Math.min(CELLS - 1, Math.max(0, Math.floor(rows[k * 9] * CELLS))), cy = Math.min(CELLS - 1, Math.max(0, Math.floor(rows[k * 9 + 1] * CELLS)));
      grid[cy * CELLS + cx].push(k);
    }
    w.nodes = rows; w.grid = grid; w.count = n;
  }

  function nearest(w, x, y) {
    var cx = Math.floor(x * CELLS), cy = Math.floor(y * CELLS), best = -1, bd = REACH * REACH, rows = w.nodes;
    for (var gy = cy - 2; gy <= cy + 2; gy++) for (var gx = cx - 2; gx <= cx + 2; gx++) {
      if (gx < 0 || gy < 0 || gx >= CELLS || gy >= CELLS) continue;
      var cell = w.grid[gy * CELLS + gx];
      for (var i = 0; i < cell.length; i++) {
        var k = cell[i], dx = rows[k * 9] - x, dy = rows[k * 9 + 1] - y, d = dx * dx + dy * dy;
        if (d < bd) { bd = d; best = k; }
      }
    }
    return best;
  }

  function add(w, x, y, r, s) {
    for (var i = 0; i < w.n; i++) {
      if (!w.alive[i]) continue;
      var dx = w.x[i] - x, dy = w.y[i] - y, rr = w.r[i] + r;
      if (dx * dx + dy * dy < rr * rr * 0.6) {
        var nr = Math.sqrt(w.r[i] * w.r[i] + r * r), t = w.r[i] / (w.r[i] + r);
        if (nr > RMAX_M * (s || 0.2)) return -1;                                                    // too big to merge: the new one is simply not added
        w.x[i] = w.x[i] * t + x * (1 - t); w.y[i] = w.y[i] * t + y * (1 - t); w.r[i] = nr;
        return i;
      }
    }
    for (var j = 0; j < w.n; j++) if (!w.alive[j]) { w.x[j] = x; w.y[j] = y; w.r[j] = r; w.alive[j] = 1; w.age[j] = 0; w.life[j] = 6 + rnd(w) * 14; return j; }
    return -1;
  }

  function alive(w) { var c = 0; for (var i = 0; i < w.n; i++) c += w.alive[i]; return c; }

  // p: { rain 0..1 (falling now), wet 0..1, fx, fy, fz: the force on the water in the car's coordinates (m/s^2) }
  function step(w, dt, p) {
    if (!w.nodes || w.count === 0) return;
    var spawns = p.rain * 220 * dt;                                                          // many small drops
    while (spawns > 0) {
      if (spawns >= 1 || rnd(w) < spawns) {
        var k = Math.floor(rnd(w) * w.count), q = rnd(w);
        var sk = w.nodes[k * 9 + 8];
        add(w, w.nodes[k * 9] + (rnd(w) - 0.5) * 0.03, w.nodes[k * 9 + 1] + (rnd(w) - 0.5) * 0.03, (0.0015 + 0.0015 * q * q * q) * sk, sk);     // 1.5 to 3 mm radius: 3 to 6 mm drops
      }
      spawns -= 1;
    }
    var evapM = (1 - Math.min(p.rain * 3, 1)) * dt * (0.0003 + 0.0008 * (1 - p.wet));       // metres of radius per second a dry drop shrinks by
    for (var i = 0; i < w.n; i++) {
      if (!w.alive[i]) continue;
      var k2 = nearest(w, w.x[i], w.y[i]);
      w.age[i] += dt;
      if (w.age[i] > w.life[i]) { w.alive[i] = 0; continue; }                                // every drop is gone after a while (blown off, run off, dried)
      if (k2 < 0) continue;                                                                  // no body node near: it stays where it is until its time is up
      var b = k2 * 9, du = w.nodes[b + 2] * p.fx + w.nodes[b + 3] * p.fy + w.nodes[b + 4] * p.fz, dv = w.nodes[b + 5] * p.fx + w.nodes[b + 6] * p.fy + w.nodes[b + 7] * p.fz;
      var s = w.nodes[b + 8], len = Math.sqrt(du * du + dv * dv);
      var along = len / s;                                                                   // the pull along the panel, m/s^2
      var r = w.r[i], rm = r / s, hold = 2 + 0.03 / rm;                                      // small beads stay on any panel; one that has merged to about 4 mm radius runs on a steep one
      w.moved[i] = 0;                                          // what holds a drop: small ones stay, big ones go
      if (along > hold) {
        var v = Math.min(0.5, 0.02 * (along - hold) * (rm * 1000 / 2.5));                      // m/s
        w.x[i] += du / len * v * s * dt;
        w.y[i] += dv / len * v * s * dt;
        w.moved[i] = 1;                                                                      // the page leaves a wet trail where a drop has run
      }
      w.r[i] -= evapM * s;
      if (w.r[i] < 0.0008 * s || w.x[i] < 0 || w.x[i] > 1 || w.y[i] < 0 || w.y[i] > 1) w.alive[i] = 0;
    }
  }

  var api = { create: create, setNodes: setNodes, step: step, add: add, alive: alive, nearest: nearest, MAXD: MAXD };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.CsfxPaintWater = api;
})(this);
