// Tests that the scratch canvas page keeps scratches and splats apart (mod/vehicles/common/carSurfaceFx/scratch.js), with a stub canvas that counts what is drawn.
//   node tests/scratchjs_test.js
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const frames = {};
function page(query) {
  const ops = { strokes: 0, arcs: 0, fills: 0 };
  const ctx = new Proxy({}, {
    get: (t, k) => (k === 'stroke' ? () => ops.strokes++ : k === 'fill' ? () => ops.arcs++ : k === 'createRadialGradient' ? () => ({ addColorStop() {} }) : k === 'createImageData' ? (w, h) => ({ data: new Uint8ClampedArray(w * h * 4) }) : k === 'fillRect' ? () => ops.fills++ : () => {}),
    set: () => true,
  });
  const canvas = { getContext: () => ctx };
  const win = {};
  const sandbox = { window: win, document: { getElementById: () => canvas, createElement: () => ({ getContext: () => ctx }) }, location: { search: query }, Math,
    performance: { now: () => 0 }, requestAnimationFrame: (cb) => { frames.cb = cb; }, Float32Array, Uint8Array };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'mod', 'vehicles', 'common', 'carSurfaceFx', 'paintwater.js'), 'utf8'), sandbox);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'mod', 'vehicles', 'common', 'carSurfaceFx', 'scratch.js'), 'utf8'), sandbox);
  return { w: win, ops, reset: () => { ops.strokes = ops.arcs = ops.fills = 0; } };
}

const p = page('?m=b');
p.w.csfxLines({ l: [0.1, 0.1, 0.2, 0.2, 0.002, 0.3, 0.3, 0.4, 0.4, 0.002], c: [0.7, 0.7, 0.7], a: 0.9 });
p.w.csfxBlobs({ l: [0.5, 0.5, 0.03, 0.6, 0.6, 0.03], c: [0.3, 0.2, 0.1], a: 0.5, k: 'mud' });
p.w.csfxBlobs({ l: [0.7, 0.7, 0.03], c: [0.5, 0.4, 0.3], a: 0.5, k: 'dust' });

p.reset();
p.w.csfxWash({ dust: 0, mud: 1 });                       // washes the dust off, leaves the mud
assert(p.ops.arcs >= 14 && p.ops.arcs <= 26, 'the dust is gone, two mud splatters (a body and droplets each) are redrawn: ' + p.ops.arcs);
assert.strictEqual(p.ops.strokes, 4, 'both scratches are redrawn (2 passes x 2 lines): washing keeps them');

p.reset();
p.w.csfxWash({ dust: 0.5, mud: 0.01 });                  // mud nearly gone: dropped
assert.strictEqual(p.ops.arcs, 0, 'faded-out splats are dropped');
assert.strictEqual(p.ops.strokes, 4, 'scratches still there');

p.w.csfxBlobs({ l: [0.2, 0.8, 0.03], c: [0.3, 0.2, 0.1], a: 0.5, k: 'mud' });
p.reset();
p.w.csfxRepair();
assert.strictEqual(p.ops.strokes, 0, 'repair removes the scratches');
assert(p.ops.arcs >= 7, 'and leaves the dirt: ' + p.ops.arcs);

p.w.csfxClear();
p.reset();
p.w.csfxWash({ mud: 1 });
assert.strictEqual(p.ops.arcs + p.ops.strokes, 0, 'clear removes everything');

// sprayed mud: a blob with a direction is drawn as an elongated splat with a streak and droplets
p.reset();
p.w.csfxBlobs({ l: [0.3, 0.3, 0.02], d: [0.8, 0.6], c: [0.3, 0.2, 0.1], a: 0.7, k: 'mud' });
assert(p.ops.arcs >= 7, 'a sprayed splat has a streak: ' + p.ops.arcs + ' arcs');

const pal = page('?m=p');                                // the palette page never draws splats
pal.w.csfxBlobs({ l: [0.5, 0.5, 0.03], c: [0.3, 0.2, 0.1], a: 0.5, k: 'mud' });
assert.strictEqual(pal.ops.arcs, 0, 'splats are base page only');
// the running drops through the page, as the game side drives it: the node map in pieces, the debug switch, a few frames
const wp = page('?m=b');
const rows = [];
for (let i = 0; i < 20; i++) for (let j = 0; j < 20; j++) rows.push(0.4 + i * 0.01, 0.4 + j * 0.01, 0, 0.2, 0, 0, 0, -0.2, 0.2);
for (let i = 0; i < rows.length; i += 90) wp.w.csfxNodes(rows.slice(i, i + 90), i > 0 ? 1 : 0);
wp.w.csfxWater({ rain: 1, wet: 1, fx: 0, fy: 0, fz: -9.8 });
wp.w.csfxDebug(1);
wp.reset();
let now = 0;
for (let i = 0; i < 20; i++) { now += 100; frames.cb(now); }
assert(wp.ops.arcs > 20, 'drops are drawn as the page runs (got ' + wp.ops.arcs + ' disc draws)');
// a clod of mud is drawn (a ring of lumps, a lit top, droplets) and washes with the mud
{
  const c = page('?m=b');
  c.w.csfxBlobs({ l: [0.4, 0.4, 0.05], c: [0.25, 0.17, 0.1], a: 0.9, k: 'cake' });
  assert(c.ops.arcs >= 12, 'a clod is a ring of lumps, a top and droplets: ' + c.ops.arcs);
  c.reset(); c.w.csfxWash({ dust: 1, mud: 0.01 });
  assert.strictEqual(c.ops.arcs, 0, 'a clod washes away with the mud');
}
console.log('carSurfaceFx scratch page: ok');
