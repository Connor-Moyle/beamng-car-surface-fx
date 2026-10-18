// Tests of the water on the paint (mod/vehicles/common/carSurfaceFx/paintwater.js).   node tests/paintwater_test.js
const assert = require('assert');
const W = require('../mod/vehicles/common/carSurfaceFx/paintwater.js');

// a 1 m x 1 m door: texture (x, y) = (car y, car z) with 0.2 texture units per metre; "up" in the car (z) increases... y is DOWN the page, so dy/dz = -0.2
// rows: x, y, jux, juy, juz, jvx, jvy, jvz, s
function panel(vertical) {
  const rows = [];
  for (let i = 0; i < 20; i++) for (let j = 0; j < 20; j++) {
    const x = 0.4 + i * 0.01, y = 0.4 + j * 0.01;
    rows.push(x, y, 0, vertical ? 0.2 : 0.2, 0, 0, vertical ? 0 : 0.2, vertical ? -0.2 : 0, 0.2);   // vertical: x follows car y, y follows -car z; horizontal: x follows car y, y follows car x
  }
  return rows;
}
const gravity = { rain: 0, wet: 1, fx: 0, fy: 0, fz: -9.8 };

let w = W.create(); W.setNodes(w, panel(true));
let d = W.add(w, 0.5, 0.45, 0.006);
for (let i = 0; i < 30; i++) W.step(w, 1 / 30, gravity);
assert(w.y[d] > 0.45, 'a big drop runs down a vertical panel');

w = W.create(); W.setNodes(w, panel(true));
d = W.add(w, 0.5, 0.45, 0.0015 + 0.0002);
for (let i = 0; i < 30; i++) W.step(w, 1 / 30, { rain: 1, wet: 1, fx: 0, fy: 0, fz: -9.8 });
const small = W.alive(w);
assert(small > 0, 'rain makes drops');

w = W.create(); W.setNodes(w, panel(false));
d = W.add(w, 0.5, 0.45, 0.006);
for (let i = 0; i < 30; i++) W.step(w, 1 / 30, gravity);
assert(Math.abs(w.y[d] - 0.45) < 1e-6, 'gravity does not move a drop on a horizontal panel');
for (let i = 0; i < 30; i++) W.step(w, 1 / 30, { rain: 0, wet: 1, fx: 0, fy: 30, fz: -9.8 });   // a hard wind along the car pushes it along the roof
assert(w.x[d] > 0.5, 'the wind pushes it along a horizontal panel');

w = W.create(); W.setNodes(w, panel(true));
d = W.add(w, 0.5, 0.45, 0.0005);
for (let i = 0; i < 60; i++) W.step(w, 1 / 30, gravity);
assert(Math.abs(w.y[d] - 0.45) < 0.02 || !w.alive[d], 'a tiny drop stays put (or dries)');

w = W.create(); W.setNodes(w, panel(true));
d = W.add(w, 0.9, 0.9, 0.006);                                                                // no body node within reach: off the mapped paint
W.step(w, 1 / 30, gravity);
assert.strictEqual(w.alive[d], 1, 'a drop away from every body node stays put');
assert(Math.abs(w.y[d] - 0.9) < 1e-6, '...and does not move');
for (let i = 0; i < 30 * 30; i++) W.step(w, 1 / 30, { rain: 0, wet: 1, fx: 0, fy: 0, fz: 0 });
assert.strictEqual(w.alive[d], 0, 'every drop is gone after a while');

w = W.create(); W.setNodes(w, panel(true));
const a = W.add(w, 0.5, 0.5, 0.0004, 0.2), b = W.add(w, 0.5, 0.5, 0.0003, 0.2);
assert.strictEqual(a, b, 'drops that meet merge');
const c = W.add(w, 0.5, 0.5, 0.0095);
assert.strictEqual(c, -1, 'but not into something bigger than a drop');
// real size: a drop that rain makes is 1.5 to 6 mm in radius whatever the texture density of the car
for (const dens of [0.1, 0.4]) {
  const ws = W.create(); const rows = [];
  for (let i = 0; i < 20; i++) for (let j = 0; j < 20; j++) rows.push(0.4 + i * 0.01, 0.4 + j * 0.01, 0, dens, 0, 0, 0, -dens, dens);
  W.setNodes(ws, rows);
  for (let i = 0; i < 30; i++) W.step(ws, 1 / 30, { rain: 1, wet: 1, fx: 0, fy: 0, fz: 0 });
  let maxm = 0, n = 0; for (let i = 0; i < ws.n; i++) if (ws.alive[i]) { maxm = Math.max(maxm, ws.r[i] / dens); n++; }
  assert(n > 50 && maxm > 0.0012 && maxm <= 0.0061, 'drops are millimetres at density ' + dens + ': ' + (maxm * 1000).toFixed(1) + ' mm, ' + n + ' drops');
}

w = W.create(); W.setNodes(w, panel(true)); d = W.add(w, 0.5, 0.45, 0.003);
for (let i = 0; i < 30 * 40; i++) W.step(w, 1 / 30, { rain: 0, wet: 0, fx: 0, fy: 0, fz: 0 });
assert.strictEqual(w.alive[d], 0, 'drops dry up');
// the size in millimetres and the amount are settings: bigger drops at 9 mm, none lost at 1 mm, more drops at a higher amount
{
  const rows = []; for (let i = 0; i < 20; i++) for (let j = 0; j < 20; j++) rows.push(0.4 + i * 0.01, 0.4 + j * 0.01, 0, 0.2, 0, 0, 0, -0.2, 0.2);
  const run = (mm, amount) => { const ws = W.create(); W.setNodes(ws, rows); for (let i = 0; i < 20; i++) W.step(ws, 1 / 30, { rain: 1, wet: 1, fx: 0, fy: 0, fz: 0, mm, amount }); let n = 0, r = 0; for (let i = 0; i < ws.n; i++) if (ws.alive[i]) { n++; r += ws.r[i] / 0.2; } return { n, mean: r / Math.max(1, n) }; };
  const small = run(1, 1), mid = run(4.5, 1), big = run(9, 1), many = run(4.5, 2);
  assert(small.n > 20 && small.mean < mid.mean && mid.mean < big.mean, 'the size setting scales the drops: ' + [small.mean, mid.mean, big.mean].map((x) => (x * 1000).toFixed(2)).join(' < ') + ' mm radius');
  assert(many.n > mid.n * 1.3, 'the amount setting makes more drops: ' + many.n + ' against ' + mid.n);
}
// the animation rate: 0 keeps every drop where it is, 2 runs them faster; in rain a drop grows
{
  const rows = []; for (let i = 0; i < 20; i++) for (let j = 0; j < 20; j++) rows.push(0.4 + i * 0.01, 0.4 + j * 0.01, 0, 0.2, 0, 0, 0, -0.2, 0.2);
  const run = (anim) => { const ws = W.create(); W.setNodes(ws, rows); const d = W.add(ws, 0.5, 0.45, 0.006, 0.2, 1); for (let i = 0; i < 40; i++) W.step(ws, 1 / 30, { rain: 0, wet: 1, fx: 0, fy: 0, fz: -9.8, anim }); return ws.y[d]; };
  assert(Math.abs(run(0) - 0.45) < 1e-6 && run(1) > 0.46 && run(2) > run(1), 'the animation rate scales how fast the drops run: ' + run(0) + ' ' + run(1) + ' ' + run(2));
  const grow = W.create(); W.setNodes(grow, rows); const g = W.add(grow, 0.5, 0.5, 0.0004, 0.2, 1); const r0 = grow.r[g];
  for (let i = 0; i < 300; i++) W.step(grow, 1 / 30, { rain: 0.5, wet: 1, fx: 0, fy: 0, fz: 0 });
  assert(!grow.alive[g] || grow.r[g] > r0, 'in the rain a drop grows');
}
console.log('carSurfaceFx paint water: ok');
