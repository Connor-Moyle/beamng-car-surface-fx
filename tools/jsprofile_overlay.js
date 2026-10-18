// What the cockpit overlay (mod/ui/modModules/csfxRain/csfxRain.js) draws per drawn frame on a big screen, in rain, with a stub canvas that counts calls and pixels.
//   node tools/jsprofile_overlay.js [path to a csfxRain.js]     (default: this tree's; `git show master:mod/ui/modModules/csfxRain/csfxRain.js > /tmp/old.js` for a before/after)
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const file = process.argv[2] || path.join(__dirname, '..', 'mod', 'ui', 'modModules', 'csfxRain', 'csfxRain.js');
const W = Number(process.env.W) || 3440, H = Number(process.env.H) || 1440;
const t = { draws: 0, fills: 0, clears: 0, strokes: 0, px: 0 };
function ctxFor() {
  return new Proxy({}, {
    get(_, k) {
      switch (k) {
        case 'drawImage': return (img, a, b, c, d, e, f, g, h) => { t.draws++; t.px += (g !== undefined ? g * h : (typeof c === 'number' ? c * d : (img && img.width ? img.width * img.height : 0))); };
        case 'fillRect': return (x, y, w, h) => { t.fills++; t.px += w * h; };
        case 'clearRect': return (x, y, w, h) => { t.clears++; t.px += w * h; };
        case 'stroke': return () => { t.strokes++; };
        case 'createImageData': return (w, h) => ({ data: new Uint8ClampedArray(w * h * 4) });
        default: return () => {};
      }
    },
    set() { return true; },
  });
}
const mk = () => ({ width: W, height: H, style: {}, getContext: ctxFor, appendChild() {} });
let now = 0, cb = null;
const win = { innerWidth: W, innerHeight: H, requestAnimationFrame: (f) => { cb = f; } };
const doc = { createElement: () => mk(), body: { appendChild() {} } };
const sandbox = Object.assign(win, { document: doc, Math, Float32Array, Uint8Array, Uint8ClampedArray, console, __csfxScreenTest: true });      // (the stub window is the page's global object, as in a browser)
win.window = win;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox);
const ov = win.__csfxScreenCreate(doc, win);
const hull = [0.22, 0.30, 0.78, 0.30, 0.74, 0.68, 0.26, 0.68];
function scenario(label, p, frames = 600) {
  ov.handle('csfxScreen', Object.assign({ on: true, hull, rain: 0, wet: 1, speed: 12, aLong: 0, aLat: 0, wiper: 0, size: 4.5, spray: 0, frost: 0 }, p));
  for (let i = 0; i < 300; i++) { now += 1000 / 60; if (cb) { const c = cb; cb = null; c(now); } }          // warm up: drops build
  Object.keys(t).forEach((k) => (t[k] = 0));
  let drawn = 0;
  for (let i = 0; i < frames; i++) { now += 1000 / 60; if (cb) { const c = cb; cb = null; c(now); } }
  drawn = Math.round(frames / 2);                                                         // (it draws every second 60 Hz frame)
  const f = (v, n = 1) => (v / drawn).toFixed(n).padStart(9);
  console.log(label.padEnd(38) + f(t.draws) + f(t.fills + t.clears) + f(t.strokes) + f(t.px / 1e6, 2) + '   (per drawn frame: drawImage, fills+clears, strokes, Mpx)');
}
console.log('overlay on ' + W + 'x' + H + ' (' + path.basename(path.dirname(file)) + '/' + path.basename(file) + ')');
scenario('rain 0.3', { rain: 0.3 });
scenario('rain 1', { rain: 1 });
scenario('rain 1, wipers', { rain: 1, wiper: 1 });
scenario('rain 1, wipers, spray, frost', { rain: 1, wiper: 1, spray: 0.8, frost: 0.4 });
scenario('dry but wet glass', { rain: 0 });
