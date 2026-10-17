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
assert(S.count(d) <= Math.floor(120 / 1.4) + 3, 'a window carries a limited number of drops');
console.log('carSurfaceFx sim: ok');
