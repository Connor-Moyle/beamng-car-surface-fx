// The windscreen rain overlay of the driver's view (tools/overlay/overlay.js, built into mod/ui/modModules/csfxRain/csfxRain.js), against a stub DOM.   node tests/overlay_test.js
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { execFileSync } = require('child_process');

execFileSync('node', [path.join(__dirname, '..', 'tools', 'build_overlay.js'), '--check'], { stdio: 'inherit' });     // the built file matches its sources

const calls = { clip: 0, draws: 0, clears: 0, begin: 0 };
const ctx = new Proxy({}, {
  get: (t, k) => (k === 'clip' ? () => calls.clip++ : k === 'drawImage' ? () => calls.draws++ : k === 'clearRect' ? () => calls.clears++ : k === 'beginPath' ? () => calls.begin++
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

o.handle('csfxScreen', { on: false });
rafCb(t + 33);
assert.strictEqual(o.root.style.display, 'none', 'hidden again');
const before = calls.draws;
o.handle('csfxScreen', { on: true, hull: [0.1], rain: 1 });                // a broken hull draws nothing
t += 33; rafCb(t);
assert.strictEqual(calls.draws, before, 'no hull, no drops');
console.log('carSurfaceFx overlay: ok');
