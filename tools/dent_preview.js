// Draws test dents with the real mod/vehicles/common/carSurfaceFx/scratch.js (in jsdom with node-canvas) on both paint pages and composes them the way the paint shader does
// (base colour x palette tint: the palette's alpha says how much of the paint colour is applied), to look at the dent offline.
//   node tools/dent_preview.js out.png      (needs jsdom and canvas: NODE_PATH=<qa>/node_modules)
const fs = require('fs'), path = require('path');
const { JSDOM } = require('jsdom');
const { createCanvas, loadImage } = require('canvas');
const code = fs.readFileSync(path.join(__dirname, '..', 'mod', 'vehicles', 'common', 'carSurfaceFx', 'scratch.js'), 'utf8');

function page(m, dents) {
  const dom = new JSDOM('<!doctype html><body><canvas id="csfxScratchCanvas"></canvas></body>', { url: 'http://x/scratch.html?m=' + m, runScripts: 'outside-only', pretendToBeVisual: true });
  const w = dom.window;
  w.eval(code);
  dents.forEach((d) => w.csfxDent(d));
  return new Promise((res) => setTimeout(() => { res(w.document.getElementById('csfxScratchCanvas')); }, 120));
}

(async () => {
  const dents = [
    { x: 0.2, y: 0.5, r: 0.012, ang: -2.35, d: 0.15 }, { x: 0.4, y: 0.5, r: 0.025, ang: -2.35, d: 0.5 }, { x: 0.65, y: 0.5, r: 0.045, ang: -2.35, d: 1 },
    { x: 0.2, y: 0.8, r: 0.03, ang: 0, d: 0.6 }, { x: 0.45, y: 0.8, r: 0.03, ang: 1.57, d: 0.6 }, { x: 0.7, y: 0.8, r: 0.03, ang: 3.14, d: 0.6 },
  ];
  const b = await page('b', dents), p = await page('p', dents);
  const W = 1024, out = process.argv[2] || 'dent_preview.png';
  const paints = [[0.75, 0.1, 0.1], [0.1, 0.25, 0.7], [0.85, 0.85, 0.82], [0.12, 0.12, 0.14]];
  const sheet = createCanvas(W * 2, W * 2), sx = sheet.getContext('2d');
  paints.forEach((paint, n) => {
    const bc = b.getContext('2d').getImageData(0, 0, W, W), pc = p.getContext('2d').getImageData(0, 0, W, W);
    const img = sx.createImageData(W, W);
    for (let i = 0; i < W * W * 4; i += 4) {
      const a = pc.data[i + 3] / 255;                                  // the palette alpha: 1 = paint colour everywhere, gone = base colour as it is
      for (let k = 0; k < 3; k++) {
        const base = Math.pow(bc.data[i + k] / 255, 1 / 2.2);          // the canvas holds linear colour (pre-darkened by 2.2)
        const tint = a * paint[k] + (1 - a) * 1;
        img.data[i + k] = Math.round(Math.min(1, base * tint) * 255);
      }
      img.data[i + 3] = 255;
    }
    const tile = createCanvas(W, W); tile.getContext('2d').putImageData(img, 0, 0);
    sx.drawImage(tile, (n % 2) * W, Math.floor(n / 2) * W);
  });
  fs.writeFileSync(out, sheet.toBuffer('image/png'));
  console.log('written ' + out);
})();
