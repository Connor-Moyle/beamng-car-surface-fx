"""Checks the generated mark textures and materials (python tools/check_marks.py [marks folder]): every file the materials name exists with the right size and mode, the
strips tile along v (the step from the last row to the first is no bigger than an ordinary step), the opacity is empty at the sides of a strip, the normals are unit length
and flat on average, nothing is fully black or fully transparent, and the materials carry the fields the game's own decal road materials have."""
import json
import os
import sys

import numpy as np
from PIL import Image

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'mod', 'art', 'surfacefx', 'marks')
mats = json.load(open(os.path.join(root, 'main.materials.json')))
index = json.load(open(os.path.join(root, 'marks_index.json')))['types']
problems = []


def bad(msg):
    problems.append(msg)


def load(path):
    return Image.open(path)


for name, m in mats.items():
    for field in ('mapTo', 'class', 'Stages', 'translucent', 'translucentZWrite', 'materialTag0', 'version'):
        if field not in m:
            bad(f'{name}: no {field}')
    if m.get('mapTo') != name or m.get('class') != 'Material' or m.get('translucent') is not True:
        bad(f'{name}: wrong header')
    st = m['Stages'][0]
    for k in ('baseColorMap', 'normalMap', 'opacityMap', 'roughnessMap'):
        p = st.get(k)
        if not p or not p.startswith('/art/surfacefx/marks/'):
            bad(f'{name}: {k} = {p}')
            continue
        if not os.path.isfile(os.path.join(root, p[len('/art/surfacefx/marks/'):])):
            bad(f'{name}: {k} missing file {p}')
    if 'ambientOcclusionMap' in st and not os.path.isfile(os.path.join(root, st['ambientOcclusionMap'][len('/art/surfacefx/marks/'):])):
        bad(f'{name}: ao file missing')

total = 0
for t in index:
    n = t['type']
    d = os.path.join(root, n)
    blob = t['blob']
    files = {k: os.path.join(d, f't_{n}_{k}.png') for k in ('b.color', 'o.data', 'nm.normal', 'r.data')}
    w, h = t['size']
    for k, f in files.items():
        if not os.path.isfile(f):
            bad(f'{n}: {k} missing')
            continue
        im = load(f)
        total += os.path.getsize(f)
        if im.size != (w, h):
            bad(f'{n}: {k} is {im.size}, expected {(w, h)}')
        if (k in ('b.color', 'nm.normal') and im.mode != 'RGB') or (k in ('o.data', 'r.data') and im.mode != 'L'):
            bad(f'{n}: {k} has mode {im.mode}')
    col = np.asarray(load(files['b.color']), np.float32) / 255
    op = np.asarray(load(files['o.data']), np.float32) / 255
    nm = np.asarray(load(files['nm.normal']), np.float32) / 255
    if op.max() < 0.3:
        bad(f'{n}: opacity is nearly empty')
    if col.mean() < 0.01 and n != 'oil':
        bad(f'{n}: colour is black')
    vec = nm * 2 - 1
    ln = np.sqrt((vec ** 2).sum(-1))
    if abs(ln.mean() - 1) > 0.06:
        bad(f'{n}: normals are not unit length ({ln.mean():.3f})')
    if vec[..., 2].mean() < 0.7 and n != 'test_bump':
        bad(f'{n}: normals lean too far from flat (z {vec[..., 2].mean():.2f})')
    if not blob and n != 'test_bump':
        if op[:, 0].max() > 0.02 or op[:, -1].max() > 0.02:
            bad(f'{n}: the opacity is not empty at the sides ({op[:, 0].max():.2f}, {op[:, -1].max():.2f})')
    if not blob:
        for label, arr in (('colour', col), ('opacity', op), ('normal', nm)):
            a = arr.reshape(arr.shape[0], -1)
            wrap = np.abs(a[0] - a[-1]).mean()
            step = np.abs(a[1:] - a[:-1]).mean()
            if wrap > 2.5 * step + 0.01:
                bad(f'{n}: {label} does not tile along v (wrap step {wrap:.4f} vs ordinary {step:.4f})')
    else:
        edge = np.concatenate([op[0], op[-1], op[:, 0], op[:, -1]])
        if edge.max() > 0.02:
            bad(f'{n}: the stain touches the image edge')
    for kind in ('dry', 'wet'):
        if t[kind] not in mats:
            bad(f'{n}: no material {t[kind]}')
print(f'{len(index)} types, {len(mats)} materials, {total / 1e6:.1f} MB of png')
if problems:
    print('PROBLEMS:')
    for p in problems:
        print('  ', p)
    sys.exit(1)
print('marks check passed')
