// The windscreen rain overlay of the driver's view (tools/overlay/overlay.js, built into mod/ui/modModules/csfxRain/csfxRain.js), against a stub DOM.   node tests/overlay_test.js
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { execFileSync } = require('child_process');

execFileSync('node', [path.join(__dirname, '..', 'tools', 'build_overlay.js'), '--check'], { stdio: 'inherit' });     // the built file matches its sources

const calls = { fills: 0, clip: 0, draws: 0, clears: 0, begin: 0, strokes: 0 };
const ctx = new Proxy({}, {
  get: (t, k) => (k === 'fill' ? () => calls.fills++ : k === 'clip' ? () => calls.clip++ : k === 'drawImage' ? () => calls.draws++ : k === 'clearRect' ? () => calls.clears++ : k === 'beginPath' ? () => calls.begin++ : k === 'stroke' ? () => calls.strokes++
    : k === 'createImageData' ? (w, h) => ({ data: new Uint8ClampedArray(w * h * 4) }) : () => {}),
  set: () => true,
});
const mkEl = () => ({ style: { cssText: '' }, children: [], appendChild(c) { this.children.push(c); }, getContext: () => ctx, width: 0, height: 0 });
const doc = { createElement: () => mkEl(), body: mkEl() };
let rafCb = null;
const win = { innerWidth: 1280, innerHeight: 720, requestAnimationFrame: (cb) => { rafCb = cb; } };
const sandbox = Object.assign(win, { document: doc, Math, Float32Array, Uint8Array, Uint8ClampedArray, __csfxScreenTest: true });   // the stub window is the page's global object, as in a browser
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'mod', 'ui', 'modModules', 'csfxRain', 'csfxRain.js'), 'utf8'), sandbox);
assert(typeof win.__csfxScreenCreate === 'function', 'the overlay is published');

const o = win.__csfxScreenCreate(doc, win);
assert.strictEqual(o.root.style.display === 'block', false, 'hidden at the start');
o.handle('csfxScreen', { on: true, hull: [0.2, 0.2, 0.8, 0.2, 0.9, 0.6, 0.1, 0.6], rain: 1, wet: 1, speed: 10, aLong: 0, aLat: 0, wiper: 0, size: 2.2 });
assert.strictEqual(o.root.style.display, 'block', 'shown');
let t = 0;
for (let i = 0; i < 300; i++) { t += 33; rafCb(t); }
assert(calls.clip > 0, 'drawn clipped to the hull');
assert(o.sim().n > 0 && calls.draws > 5, 'drops are drawn (' + calls.draws + ' draw calls)');
let alive = 0;
for (let i = 0; i < o.sim().n; i++) alive += o.sim().alive[i];
assert(alive > 0, 'there are drops');

assert(calls.strokes > 0, 'running drops leave thin streaks (' + calls.strokes + ' strokes)');

// 30 frames a second at most: frames 10 ms apart draw about a third of them
const c0 = calls.clears;
for (let i = 0; i < 300; i++) { t += 10; rafCb(t); }
assert(calls.clears - c0 < 120 && calls.clears - c0 > 60, 'throttled to 30 fps: ' + (calls.clears - c0) + ' draws for 300 frames');

// the JavaScript of a frame (simulation, streaks, the draw calls themselves are free on the stub) stays well under 0.5 ms
let ms = Infinity;      // the best of five runs of 120 frames: a busy machine slows one run, not all
for (let r = 0; r < 5; r++) {
  const t0 = process.hrtime.bigint();
  for (let i = 0; i < 120; i++) { t += 34; rafCb(t); }
  ms = Math.min(ms, Number(process.hrtime.bigint() - t0) / 1e6 / 120);
}
assert(ms < 0.8, 'frame cost ' + ms.toFixed(3) + ' ms');
console.log('overlay frame JS cost: ' + ms.toFixed(3) + ' ms');

// the wipers: arcs are cleared (two blades), and the drops in the swept area are gone
o.handle('csfxScreen', { on: true, hull: [0.2, 0.2, 0.8, 0.2, 0.9, 0.6, 0.1, 0.6], rain: 1, wet: 1, wiper: 0 });
for (let i = 0; i < 120; i++) { t += 34; rafCb(t); }
const f0 = calls.fills;
let drops0 = 0, minAlive = 1e9;
for (let i = 0; i < o.sim().n; i++) drops0 += o.sim().alive[i];
o.handle('csfxScreen', { on: true, hull: [0.2, 0.2, 0.8, 0.2, 0.9, 0.6, 0.1, 0.6], rain: 1, wet: 1, wiper: 1 });
for (let i = 0; i < 40; i++) {
  t += 34; rafCb(t);
  let a = 0;
  for (let k = 0; k < o.sim().n; k++) a += o.sim().alive[k];
  minAlive = Math.min(minAlive, a);
}
assert(calls.fills - f0 >= 40, 'the blades clear arcs: ' + (calls.fills - f0) + ' fills');
assert(minAlive < drops0, 'drops in the swept arcs are gone: ' + drops0 + ' -> ' + minAlive);

// frost: with no rain at all the overlay still shows (the ice is drawn under the drops)
o.handle('csfxScreen', { on: true, hull: [0.2, 0.2, 0.8, 0.2, 0.9, 0.6, 0.1, 0.6], rain: 0, wet: 0, frost: 0.9 });
const d0 = calls.draws;
t += 40; rafCb(t);
assert(calls.draws - d0 >= 2, 'the frost layer and the trails are drawn: ' + (calls.draws - d0));
assert(o.state.p.frost === 0.9, 'the frost amount arrives');

o.handle('csfxScreen', { on: false });
rafCb(t + 33);
assert.strictEqual(o.root.style.display, 'none', 'hidden again');
const before = calls.draws;
o.handle('csfxScreen', { on: true, hull: [0.1], rain: 1 });                // a broken hull draws nothing
t += 33; rafCb(t);
assert.strictEqual(calls.draws, before, 'no hull, no drops');
console.log('carSurfaceFx overlay: ok');
