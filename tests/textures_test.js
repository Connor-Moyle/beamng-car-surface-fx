// Texture rules of the game's NOTE_FOR_MODDERS.md (rule 6): a texture the engine loads ships as DDS only, named *.color / *.normal / *.data, and the materials keep naming the .png.
// PNGs that are not engine textures are listed below with the reason. A badly named or uncooked texture fails here.   node tests/textures_test.js
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const MOD = path.join(__dirname, '..', 'mod');
const ROLE = /\.(color|normal|data)\.(png|dds)$/i;
// PNGs that stay PNG: read by the Mods page / the paint canvas as plain images, or picked up by name from a player-droppable folder
const PNG_OK = [
  ['art/decals/', 'ground-mark and glass decals: the player drops their own PNGs here (texlist.lua scans *.png)'],
  ['art/surfacefx/splats/', 'read by the paint page (scratch.js) as an image'],
  ['art/surfacefx/dirt/', 'masks read by the paint page as images'],
  ['art/surfacefx/probe_white.png', 'dev decal probe, not a material texture'],
];

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    e.isDirectory() ? walk(p, out) : out.push(p);
  }
  return out;
}
const rel = (p) => path.relative(MOD, p).split(path.sep).join('/');
const files = walk(path.join(MOD, 'art')).map(rel);
const have = new Set(files.map((f) => f.toLowerCase()));

// 1. every DDS is named by its role; every PNG is either allowed (with a reason) or named by its role and cooked
for (const f of files) {
  if (/\.dds$/i.test(f)) assert(ROLE.test(f), 'a DDS must be named *.color / *.normal / *.data: ' + f);
  if (/\.png$/i.test(f)) {
    if (PNG_OK.some(([p]) => f.startsWith(p))) continue;
    assert.fail('a PNG ships next to nothing it can be allowed as: ' + f + ' (cook it to DDS and delete the PNG, or list it in PNG_OK with the reason)');
  }
}

// 2. every texture a material names (/art/....png) exists as a DDS, and is named by its role
let named = 0;
for (const f of walk(MOD).filter((p) => /\.json$/i.test(p))) {
  const text = fs.readFileSync(f, 'utf8');
  for (const m of text.matchAll(/"\/?(art\/[^"]+\.png)"/gi)) {
    const png = m[1];
    if (PNG_OK.some(([p]) => png.startsWith(p))) continue;
    named++;
    assert(ROLE.test(png), 'a material texture must be named *.color / *.normal / *.data: ' + png + ' in ' + rel(f));
    assert(have.has(png.replace(/\.png$/i, '.dds').toLowerCase()), 'a material names ' + png + ' but its DDS is not shipped (' + rel(f) + ')');
  }
}
assert(named > 0, 'the material scan found no texture: the test is broken');

// 3. the same for the textures Lua builds materials from
for (const f of walk(path.join(MOD, 'lua')).filter((p) => /\.lua$/i.test(p))) {
  for (const m of fs.readFileSync(f, 'utf8').matchAll(/'\/?(art\/surfacefx\/[^'%]+\.(?:color|normal|data)\.png)'/gi)) {
    assert(have.has(m[1].replace(/\.png$/i, '.dds').toLowerCase()), 'Lua names ' + m[1] + ' but its DDS is not shipped (' + rel(f) + ')');
  }
}
// (art/surfacefx/droplets%d.normal.png is built with a format: checked by hand here)
for (let k = 1; k <= 5; k++) assert(have.has('art/surfacefx/droplets' + k + '.normal.dds'), 'droplets' + k + '.normal.dds is not shipped');

console.log('textures ok: %d DDS, %d allowed PNGs, %d material references checked', files.filter((f) => /\.dds$/i.test(f)).length, files.filter((f) => /\.png$/i.test(f)).length, named);
