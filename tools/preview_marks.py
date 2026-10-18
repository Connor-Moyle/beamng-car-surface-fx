"""Lit previews of the mark textures (what they should look like in sun, shade and wet) over a ground colour, as a contact sheet:

    python tools/preview_marks.py [marks folder] [out.png]

Simple model: base colour x (ambient + sun x N.L) plus a specular lobe from the roughness, the opacity blends the mark over the ground. The wet column is darker with a
lower roughness (the wet material's factors). A strip is shown twice, one under the other, to show that it tiles along its length. Not the game's renderer: a check that
the maps read as ruts, scratches and puddles, and that nothing tiles badly.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'mod', 'art', 'surfacefx', 'marks')
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, '..', '..', '..', '..', 'docs', 'marks_preview.png')
index = json.load(open(os.path.join(root, 'marks_index.json')))
green_down = 'DirectX' in index.get('normalConvention', 'DirectX')

GROUND = {'dirt': (0.30, 0.22, 0.15), 'gravel': (0.34, 0.31, 0.27), 'sand': (0.55, 0.45, 0.30), 'mud': (0.17, 0.12, 0.08), 'snow': (0.78, 0.82, 0.88)}


def ground_for(name):
    for k, c in GROUND.items():
        if name.endswith(k) and not name.startswith('gouge_asphalt'):
            return c
    return (0.16, 0.16, 0.17)                                          # tarmac


def load(path, mode):
    return np.asarray(Image.open(path).convert(mode), np.float32) / 255


def render(name, ground, sun, wet, tiles=2):
    d = os.path.join(root, name)
    col = load(os.path.join(d, f't_{name}_b.color.png'), 'RGB')
    op = load(os.path.join(d, f't_{name}_o.data.png'), 'L')
    nm = load(os.path.join(d, f't_{name}_nm.normal.png'), 'RGB')
    rp = os.path.join(d, f't_{name}_r.data.png')
    fluid = name in ('oil', 'coolant', 'fuel')
    if fluid and not wet:
        rp = os.path.join(d, f't_{name}_r_dry.data.png')
    rough = load(rp, 'L')
    if wet and not fluid:
        col, rough = col * 0.8, rough * 0.4
    if not wet and fluid:
        op = op * 0.7
    nx, nz = nm[..., 0] * 2 - 1, nm[..., 2] * 2 - 1
    ny = (0.5 - nm[..., 1]) * 2 if green_down else (nm[..., 1] - 0.5) * 2
    ln = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    if tiles > 1 and not fluid:
        stack = lambda a: np.concatenate([a] * tiles, axis=0)
        col, op, nx, ny, nz, rough = stack(col), stack(op), stack(nx), stack(ny), stack(nz), stack(rough)
    L = np.array([0.6, -0.35, 0.5]) if sun else np.array([0.0, 0.0, 1.0])
    L = L / np.linalg.norm(L)
    ndl = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    amb = 0.35 if sun else 0.55
    lit = col * (amb + (0.9 if sun else 0.0) * ndl[..., None])
    H = L + np.array([0, 0, 1.0])
    H = H / np.linalg.norm(H)
    ndh = np.clip(nx * H[0] + ny * H[1] + nz * H[2], 0, 1)
    power = np.clip(2.0 / np.maximum(rough, 0.04) ** 2 - 2, 2, 600)
    spec = (ndh ** power) * (1 - rough) * (0.8 if sun else 0.15) * (power + 8) / 40
    img = lit + spec[..., None]
    g = np.array(ground)[None, None, :]
    g = g * ((0.35 + (0.9 if sun else 0.0) * L[2]) if sun else 0.55)
    if wet:
        g = g * 0.8
    res = g * (1 - op[..., None]) + img * op[..., None]
    return np.clip(res, 0, 1)


cells = []
for t in index['types']:
    name = t['type']
    g = ground_for(name)
    row = [render(name, g, True, False), render(name, g, False, False), render(name, g, True, True)]
    cells.append((name, row))
ph = 256
tiles = []
for name, row in cells:
    ims = []
    for a in row:
        im = Image.fromarray((a * 255).astype(np.uint8))
        s = ph / im.height
        ims.append(im.resize((max(1, int(im.width * s)), ph), Image.LANCZOS))
    tiles.append((name, ims))
cw = max(sum(i.width for i in ims) + 8 * len(ims) for _, ims in tiles)
cols = 3
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new('RGB', (cols * cw + 8, rows * (ph + 26) + 8), (24, 24, 24))
dr = ImageDraw.Draw(sheet)
for i, (name, ims) in enumerate(tiles):
    x0, y0 = 8 + (i % cols) * cw, 8 + (i // cols) * (ph + 26)
    dr.text((x0, y0), name + '   sun dry | shade dry | sun wet', fill=(255, 255, 255))
    x = x0
    for im in ims:
        sheet.paste(im, (x, y0 + 16))
        x += im.width + 8
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
sheet.save(out, optimize=True)
print('wrote', os.path.abspath(out), sheet.size)
