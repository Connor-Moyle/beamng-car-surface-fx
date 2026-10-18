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

w = W.create(); W.setNodes(w, panel(true)); d = W.add(w, 0.5, 0.45, 0.003);
for (let i = 0; i < 30 * 40; i++) W.step(w, 1 / 30, { rain: 0, wet: 0, fx: 0, fy: 0, fz: 0 });
assert.strictEqual(w.alive[d], 0, 'drops dry up');
console.log('carSurfaceFx paint water: ok');
