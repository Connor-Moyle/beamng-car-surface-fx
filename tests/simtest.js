// Tests of the window water simulation (mod/vehicles/common/carSurfaceFx/sim.js).   node tests/simtest.js
const assert = require('assert');
const S = require('../mod/vehicles/common/carSurfaceFx/sim.js');
const P = (o) => Object.assign({ rain: 0, wet: 0, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1 }, o);

let d = S.create();
for (let i = 0; i < 120; i++) S.step(d, 1 / 60, P({}));
assert.strictEqual(S.count(d), 0, 'no rain, no drops');
for (let i = 0; i < 600; i++) S.step(d, 1 / 60, P({ rain: 1, speed: 10 }));
assert(S.count(d) > 10 && S.count(d) <= S.MAX, 'rain makes a bounded number of drops');

d = S.create();
const a = S.add(d, 0.5, 0.5, 0.004), b = S.add(d, 0.5, 0.5, 0.003);
assert.strictEqual(a, b, 'a drop landing on another merges');
assert(Math.abs(d.r[a] - 0.005) < 1e-6, 'areas add');

d = S.create();
const big = S.add(d, 0.5, 0.2, 0.02);
S.step(d, 1, P({ wet: 1 }));
assert(d.y[big] > 0.2, 'a big drop runs down');
const small = S.create(); const sm = S.add(small, 0.5, 0.5, 0.005);
S.step(small, 1, P({ wet: 1 }));
assert.strictEqual(small.y[sm], 0.5, 'a small drop at rest stays');

d = S.create(); const fast = S.add(d, 0.5, 0.5, 0.008);
S.step(d, 1, P({ speed: 35, wet: 1 }));
assert(d.y[fast] < 0.5, 'speed pushes drops up the glass');

d = S.create(); const brake = S.add(d, 0.5, 0.5, 0.008);
S.step(d, 1, P({ speed: 10, aLong: -8, wet: 1 }));
assert(d.y[brake] > 0.5, 'braking throws them forward and down');

d = S.create(); const side = S.add(d, 0.5, 0.5, 0.008);
S.step(d, 1, P({ speed: 20, aLat: 8, wet: 1 }));
assert(d.x[side] !== 0.5, 'cornering slides them sideways');

d = S.create(); const w = S.add(d, 0.5, 0.5, 0.008);
for (let i = 0; i < 180; i++) S.step(d, 1 / 60, P({ wiper: 1, wet: 1 }));
assert.strictEqual(d.alive[w], 0, 'the wiper clears the drop');

d = S.create(); const e = S.add(d, 0.5, 0.5, 0.004);
for (let i = 0; i < 60 * 60; i++) S.step(d, 1 / 60, P({ wet: 0 }));
assert.strictEqual(d.alive[e], 0, 'drops dry up when the rain stops');

d = S.create(); S.add(d, 0.5, 0.2, 0.02);
for (let i = 0; i < 60; i++) S.step(d, 1 / 60, P({ wet: 1 }));
assert(S.count(d) > 1, 'a running drop leaves small ones behind');
d = S.create();
for (let i = 0; i < 600; i++) S.step(d, 1 / 60, P({ rain: 1, speed: 10, size: 1 }));
const n1 = S.count(d);
let rbig = 0, nbig = 0;
d = S.create();
for (let i = 0; i < 600; i++) S.step(d, 1 / 60, P({ rain: 1, speed: 10, size: 3 }));
for (let i = 0; i < d.n; i++) if (d.alive[i]) { rbig += d.r[i]; nbig++; }
assert(nbig > 0 && rbig / nbig > 0.006, 'size scales the drops up');
d = S.create();
for (let i = 0; i < 60 * 30; i++) S.step(d, 1 / 60, P({ rain: 1, speed: 0, size: 1.4 }));
assert(S.count(d) <= Math.floor(300 / 1.4) + 3, 'a window carries a limited number of drops');
// no drop outgrows the window (this seed, rain, speed and the overlay's size used to make one thousands of pixels wide)
d = S.create(); d.seed = 12345;
let biggest = 0;
for (let i = 0; i < 60 * 90; i++) { S.step(d, 1 / 60, P({ rain: 1, speed: 8, size: 4.5 })); if (i % 30 === 0) for (let k = 0; k < d.n; k++) if (d.alive[k]) biggest = Math.max(biggest, d.r[k]); }
assert(biggest <= 0.07 * 4.5 + 1e-6 && biggest < 0.5, 'a drop never grows past the limit: ' + biggest);
// per-pane directions: with a field whose gravity runs along +u (and back along -u), a big drop runs sideways in canvas space, not down it
{
  const N = 32, mk = () => new Float32Array(N * N * 2);
  const flow = { n: N, g: mk(), b: mk(), r: mk(), ready: true };
  for (let c = 0; c < N * N; c++) { flow.g[c * 2] = 1; flow.b[c * 2] = -1; flow.r[c * 2 + 1] = 1; }
  const d = S.create();
  const i = S.add(d, 0.5, 0.5, 0.03);
  const p = { rain: 0, wet: 1, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, size: 1, flow };
  for (let k = 0; k < 20; k++) S.step(d, 0.05, p);
  assert(d.x[i] > 0.52 && Math.abs(d.y[i] - 0.5) < 1e-6, 'gravity runs along the own u of the pane: ' + d.x[i] + ', ' + d.y[i]);
  const d2 = S.create(), j = S.add(d2, 0.5, 0.5, 0.03);
  const p2 = { rain: 0, wet: 1, speed: 30, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, size: 1, flow };
  for (let k = 0; k < 20; k++) S.step(d2, 0.05, p2);
  assert(d2.x[j] < 0.5, 'the air of speed pushes along the back direction of the pane: ' + d2.x[j]);
  const fm = { n: N, g: flow.g, b: flow.b, r: flow.r, ready: true, cells: [5 * N + 7] };             // glass in one cell only: every new drop is made there
  const d4 = S.create();
  const p4 = { rain: 1, wet: 1, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, glassMm: 5, uvPerM: 0.5, amount: 1, flow: fm };
  S.step(d4, 0.05, p4);
  let seen = 0; for (let i = 0; i < d4.n; i++) if (d4.alive[i]) { seen++; assert(d4.x[i] >= 7 / N - 1e-6 && d4.x[i] <= 8 / N + 0.001 && d4.y[i] >= 5 / N - 1e-6 && d4.y[i] <= 6 / N + 0.001, 'a drop is made inside the glass cell: ' + d4.x[i] + ' ' + d4.y[i]); }
  assert(seen > 1, 'and there are some: ' + seen);
  p.flow = null;
  const d3 = S.create(), q = S.add(d3, 0.5, 0.5, 0.03);
  for (let k = 0; k < 20; k++) S.step(d3, 0.05, p);
  assert(d3.y[q] > 0.52, 'without a field the old single axis is used');
}
// window drops in millimetres: bigger at 9 mm, more at a higher amount, and the same real size for a pane with another texture density
{
  const run = (mm, amount, uv) => { const d = S.create(); for (let i = 0; i < 20; i++) S.step(d, 1 / 30, { rain: 1, wet: 1, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, glassMm: mm, amount, uvPerM: uv }); let n = 0, r = 0; for (let i = 0; i < d.n; i++) if (d.alive[i]) { n++; r += d.r[i] / uv; } return { n, mean: r / Math.max(1, n) }; };
  const a = run(3, 1, 0.5), b = run(8, 1, 0.5), c = run(5, 2, 0.5), e = run(5, 1, 0.5), f = run(5, 1, 0.25);
  assert(a.mean < b.mean, 'the millimetre setting scales the window drops: ' + a.mean + ' ' + b.mean);
  assert(c.n > e.n, 'the amount setting makes more window drops');
  assert(Math.abs(e.mean - f.mean) / e.mean < 0.35, 'the same real size at another texture density: ' + e.mean + ' vs ' + f.mean);
}
// a texture with many pane cells carries more drops than one with a windscreen's worth (the drops are per window area)
{
  const run = (ncells) => { const d = S.create(900), cells = []; for (let i = 0; i < ncells; i++) cells.push(i); const fl = { ready: true, n: 32, cells, g: new Array(2048).fill(0), b: new Array(2048).fill(0), r: new Array(2048).fill(0) }; for (let i = 0; i < 400; i++) S.step(d, 1 / 12, { rain: 1, wet: 1, speed: 0, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, glassMm: 5, amount: 1, uvPerM: 0.44, flow: fl }); return S.count(d); };
  const few = run(180), many = run(720);
  assert(many > 2 * few && many <= 900, 'more pane cells, more drops: ' + few + ' vs ' + many);
}
console.log('carSurfaceFx sim: ok');
