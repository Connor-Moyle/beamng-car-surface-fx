// Counts what the Car Surface FX web pages draw per frame (window canvases glass.js, paint canvas scratch.js + paintwater.js) with a stub canvas, in rain, and how
// that scales with the number of drops. Not a timing of the browser: the counts (draw calls, filled pixels as 1024x1024 canvases) and the time the page's own
// JavaScript takes in node (the simulation and the loops; the real fill cost comes on top and is what the counts say).
//   node tools/jsprofile.js [fps]       fps = how often the page's requestAnimationFrame fires (default 60; the web textures are made at 10-12 fps)
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const DIR = path.join(__dirname, '..', 'mod', 'vehicles', 'common', 'carSurfaceFx');
const FPS = Number(process.argv[2]) || 60;
const FULL = 1024 * 1024;

function stage(search, size) {
  const t = { calls: 0, px: 0, composite: 0, arcs: 0, strokes: 0, fills: 0, imageData: 0, draws: 0 };
  let comp = 'source-over';
  const mk = (w, h) => {
    const cv = { width: w, height: h };
    cv.getContext = () => ctx;
    return cv;
  };
  const ctx = new Proxy({}, {
    get(_, k) {
      switch (k) {
        case 'drawImage': return (img, a, b, c, d) => {
          t.calls++; t.draws++;
          const area = (typeof c === 'number' && typeof d === 'number') ? c * d : (img && img.width ? img.width * img.height : 0);
          t.px += area;
          if (comp !== 'source-over') t.composite += area;
        };
        case 'fillRect': return (x, y, w, h) => { t.calls++; t.fills++; t.px += w * h; if (comp !== 'source-over') t.composite += w * h; };
        case 'clearRect': return () => { t.calls++; };
        case 'arc': return (x, y, r) => { t.arcs++; t.px += Math.PI * r * r; };
        case 'fill': case 'stroke': return () => { t.calls++; t.strokes++; };
        case 'createRadialGradient': return () => ({ addColorStop() {} });
        case 'createImageData': return (w, h) => ({ data: new Uint8ClampedArray(w * h * 4) });
        case 'putImageData': return () => { t.imageData++; };
        case 'globalCompositeOperation': return comp;
        default: return () => {};
      }
    },
    set(_, k, v) { if (k === 'globalCompositeOperation') comp = v; return true; },
  });
  const canvas = mk(0, 0);
  let now = 0, cb = null;
  const win = { innerWidth: 512, innerHeight: 512 };
  const sandbox = {
    window: win, location: { search }, Math, Float32Array, Uint8Array, Uint8ClampedArray, RegExp, decodeURIComponent, isFinite, String, Number,
    document: { getElementById: () => canvas, createElement: () => mk(300, 150) },
    performance: { now: () => now },
    requestAnimationFrame: (f) => { cb = f; },
    Image: function () { this.complete = false; this.naturalWidth = 0; },
  };
  vm.createContext(sandbox);
  for (const f of search.includes('csfxScratch') || /[?&]m=/.test(search) ? ['paintwater.js', 'scratch.js'] : ['sim.js', 'glass.js']) {
    vm.runInContext(fs.readFileSync(path.join(DIR, f), 'utf8'), sandbox);
  }
  return {
    win, t, canvas,
    run(frames, setup) {
      const dt = 1000 / FPS;
      let cpu = 0n;
      const before = JSON.stringify(t);
      for (let i = 0; i < frames; i++) {
        now += dt;
        if (setup) setup(i);
        const c = cb; cb = null;
        const h0 = process.hrtime.bigint();
        if (c) c(now);
        cpu += process.hrtime.bigint() - h0;
      }
      const b = JSON.parse(before), d = {};
      for (const k in t) d[k] = (t[k] - b[k]) / frames;
      d.cpuMs = Number(cpu) / 1e6 / frames;
      return d;
    },
  };
}

function row(name, d, extra) {
  const f = (v, n = 1) => v.toFixed(n).padStart(8);
  console.log(name.padEnd(46) + f(d.draws) + f(d.fills) + f(d.arcs) + f(d.px / FULL, 2) + f(d.composite / FULL, 2) + f(d.cpuMs, 3) + (extra ? '  ' + extra : ''));
}
console.log(`page frames at ${FPS} Hz; per frame:`.padEnd(46) + ' drawImg   fills    arcs Mpx(1k^2) compMpx   js ms');

// ---- the window canvas (glass.js), 512x512 ----
for (const mode of ['color', 'emissive']) {
  for (const [label, p] of [['rain 0.3', { rain: 0.3 }], ['rain 1', { rain: 1 }], ['rain 1 + wiper + frost', { rain: 1, wiper: 1, frost: 0.5 }], ['dry, wet glass', { rain: 0, wet: 1 }]]) {
    const pg = stage('?mode=' + mode, 512);
    pg.win.csfxSet(Object.assign({ rain: 0, wet: 0.5, speed: 8, aLong: 0, aLat: 0, wiper: 0, gx: 0, gy: 1, tint: 1, passes: 1, flood: 0, frost: 0, size: 4.5 }, p));
    pg.run(FPS * 20);                                              // fill up
    const d = pg.run(FPS * 10);
    row(`window ${mode}: ${label}`, d, '');
  }
}

// ---- the paint canvas (scratch.js ?m=b), 1024x1024 ----
const rows = [];
for (let i = 0; i < 40; i++) for (let j = 0; j < 40; j++) rows.push(0.2 + i * 0.015, 0.2 + j * 0.015, 0, 0.2, 0, 0, 0, -0.2, 0.2);      // 1600 nodes: a car
for (const [label, wp] of [['rain 0.3', { rain: 0.3, wet: 1 }], ['rain 1', { rain: 1, wet: 1 }], ['rain 1, driving (side pull)', { rain: 1, wet: 1, fx: 4, fz: -9.8 }]]) {
  const pg = stage('?m=b', 1024);
  for (let i = 0; i < rows.length; i += 90) pg.win.csfxNodes(rows.slice(i, i + 90), i > 0 ? 1 : 0);
  pg.win.csfxWater(Object.assign({ fx: 0, fy: 0, fz: -9.8 }, wp));
  pg.run(FPS * 25);
  const d = pg.run(FPS * 10);
  row(`paint base: ${label}`, d, 'drops ' + pg.win.csfxInfo());
}
{
  const pg = stage('?m=p', 1024);
  const d = pg.run(FPS * 5);
  row('paint palette: idle (no marks changing)', d, '');
}
{
  const pg = stage('?m=b', 1024);
  const d = pg.run(FPS * 5);
  row('paint base: idle, dry', d, '');
}
