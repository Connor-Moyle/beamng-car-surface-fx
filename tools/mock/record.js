// Runs the real cockpit overlay (csfxRain.js) with a recording canvas and writes every drawing call to a JSON file, for tools/mock/replay.py to draw over a backdrop.
//   node tools/mock/record.js <out.json> [overlay.js] [width height] [rain] [frames]
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const out = process.argv[2];
const file = process.argv[3] || path.join(__dirname, '..', '..', 'mod', 'ui', 'modModules', 'csfxRain', 'csfxRain.js');
const W = Number(process.argv[4]) || 1920, H = Number(process.argv[5]) || 1080;
const RAIN = process.argv[6] !== undefined ? Number(process.argv[6]) : 0.7;
const FRAMES = Number(process.argv[7]) || 360;
const ops = [];
let nextId = 0;
let recording = false;
function mkCanvas() {
  const id = nextId++;
  let w = 300, h = 150;                                           // (a new canvas is 300 x 150; the size changes are recorded)
  const cv = { id, style: {}, appendChild() {} };
  Object.defineProperty(cv, 'width', { get: () => w, set: (v) => { w = v; ops.push([id, 'dim', w, h]); } });
  Object.defineProperty(cv, 'height', { get: () => h, set: (v) => { h = v; ops.push([id, 'dim', w, h]); } });
  ops.push([id, 'dim', w, h]);
  const state = {};
  cv.getContext = () => new Proxy({}, {
    get(_, k) {
      if (k in state) return state[k];
      if (k === 'createImageData') return (w, h) => { const d = { data: new Uint8ClampedArray(w * h * 4), width: w, height: h }; return d; };
      if (k === 'putImageData') return (img, x, y) => { if (recording || true) ops.push([id, 'putImageData', Buffer.from(img.data.buffer).toString('base64'), img.width, img.height, x, y]); };
      if (k === 'drawImage') return (img, ...a) => { if (recording || true) ops.push([id, 'drawImage', img.id, ...a]); };
      return (...a) => { if (recording || true) ops.push([id, k, ...a]); };
    },
    set(_, k, v) { state[k] = v; ops.push([id, 'set', k, v]); return true; },
  });
  return cv;
}
const main = mkCanvas();
let now = 0, cb = null;
const win = { innerWidth: W, innerHeight: H, requestAnimationFrame: (f) => { cb = f; } };
const doc = { createElement: () => mkCanvas(), body: { appendChild() {} } };
const sandbox = Object.assign(win, { document: doc, Math, Float32Array, Uint8Array, Uint8ClampedArray, console, __csfxScreenTest: true });
win.window = win;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox);
// the overlay creates its own canvas: capture it (the first createElement after document creation is its canvas element)
const ov = win.__csfxScreenCreate(doc, win);
const hull = [0.380, 0.358, 0.961, 0.353, 0.911, 0.610, 0.398, 0.612];      // the Vivace windscreen as seen in the driver camera (from a 768 x 397 screenshot)
ov.handle('csfxScreen', { on: true, hull, rain: RAIN, wet: 1, speed: 14, aLong: 0, aLat: 0, wiper: 0, size: 4.5, spray: 0, frost: 0 });
for (let i = 0; i < FRAMES; i++) { now += 1000 / 60; ops.push([-1, 'frame', i]); if (cb) { const c = cb; cb = null; c(now); } }
fs.writeFileSync(out, JSON.stringify({ W, H, hull, canvas: ov.canvas.id, ops }));
console.log('recorded', ops.length, 'calls,', FRAMES, 'frames; overlay canvas', ov.canvas.id);
