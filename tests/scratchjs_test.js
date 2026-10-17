// Tests that the scratch canvas page keeps scratches and splats apart (mod/vehicles/common/carSurfaceFx/scratch.js), with a stub canvas that counts what is drawn.
//   node tests/scratchjs_test.js
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

function page(query) {
  const ops = { strokes: 0, arcs: 0, fills: 0 };
  const ctx = new Proxy({}, {
    get: (t, k) => (k === 'stroke' ? () => ops.strokes++ : k === 'fill' ? () => ops.arcs++ : k === 'createRadialGradient' ? () => ({ addColorStop() {} }) : k === 'fillRect' ? () => ops.fills++ : () => {}),
    set: () => true,
  });
  const canvas = { getContext: () => ctx };
  const win = {};
  const sandbox = { window: win, document: { getElementById: () => canvas }, location: { search: query }, Math };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'mod', 'vehicles', 'common', 'carSurfaceFx', 'scratch.js'), 'utf8'), sandbox);
  return { w: win, ops, reset: () => { ops.strokes = ops.arcs = ops.fills = 0; } };
}

const p = page('?m=b');
p.w.csfxLines({ l: [0.1, 0.1, 0.2, 0.2, 0.002, 0.3, 0.3, 0.4, 0.4, 0.002], c: [0.7, 0.7, 0.7], a: 0.9 });
p.w.csfxBlobs({ l: [0.5, 0.5, 0.03, 0.6, 0.6, 0.03], c: [0.3, 0.2, 0.1], a: 0.5, k: 'mud' });
p.w.csfxBlobs({ l: [0.7, 0.7, 0.03], c: [0.5, 0.4, 0.3], a: 0.5, k: 'dust' });

p.reset();
p.w.csfxWash({ dust: 0, mud: 1 });                       // washes the dust off, leaves the mud
assert.strictEqual(p.ops.arcs, 2, 'the dust is gone, two mud splats are redrawn');
assert.strictEqual(p.ops.strokes, 4, 'both scratches are redrawn (2 passes x 2 lines): washing keeps them');

p.reset();
p.w.csfxWash({ dust: 0.5, mud: 0.01 });                  // mud nearly gone: dropped
assert.strictEqual(p.ops.arcs, 0, 'faded-out splats are dropped');
assert.strictEqual(p.ops.strokes, 4, 'scratches still there');

p.w.csfxBlobs({ l: [0.2, 0.8, 0.03], c: [0.3, 0.2, 0.1], a: 0.5, k: 'mud' });
p.reset();
p.w.csfxRepair();
assert.strictEqual(p.ops.strokes, 0, 'repair removes the scratches');
assert.strictEqual(p.ops.arcs, 1, 'and leaves the dirt');

p.w.csfxClear();
p.reset();
p.w.csfxWash({ mud: 1 });
assert.strictEqual(p.ops.arcs + p.ops.strokes, 0, 'clear removes everything');

const pal = page('?m=p');                                // the palette page never draws splats
pal.w.csfxBlobs({ l: [0.5, 0.5, 0.03], c: [0.3, 0.2, 0.1], a: 0.5, k: 'mud' });
assert.strictEqual(pal.ops.arcs, 0, 'splats are base page only');
console.log('carSurfaceFx scratch page: ok');
