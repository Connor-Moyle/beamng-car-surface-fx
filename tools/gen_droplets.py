"""Writes the shared water maps of the rain effect (seamless 512x512 tangent-space normal maps), mod/art/surfacefx/:
     droplets1..5.normal.png  the paint's five wet rungs: sparse small beads that grow, get more numerous and merge as the car gets wetter
     glass.normal.png         beads with vertical run-off streaks, scrolled by the glass material's UV animation
   python tools/gen_droplets.py   (needs numpy, Pillow)"""
import os, numpy as np
from PIL import Image
N = 512
OUT = os.path.join(os.path.dirname(__file__), '..', 'mod', 'art', 'surfacefx')
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)

def wrap(c, v): return np.minimum(np.abs(v - c), N - np.abs(v - c))

def cap(h, cx, cy, r):
    d2 = (wrap(cx, xx) ** 2 + wrap(cy, yy) ** 2) / (r * r)
    np.maximum(h, np.where(d2 < 1, (1 - d2) * r, 0), out=h)

def save(h, name):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    n = np.dstack([-gx, -gy, np.full_like(h, 1.0)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(OUT, name))

def layout(rng, target):
    """beads that never touch at full size, until they cover `target` of the tile; returns [(x, y, r)]"""
    placed, area, tries = [], 0.0, 0
    while area < target * N * N and tries < 30000:
        tries += 1
        r = 1.5 + 5.5 * rng.random() ** 2.5
        cx, cy = rng.uniform(0, N), rng.uniform(0, N)
        if any(wrap(x, np.float32(cx)) ** 2 + wrap(y, np.float32(cy)) ** 2 < (r + q + 3) ** 2 for x, y, q in placed): continue
        placed.append((cx, cy, r)); area += np.pi * r * r
    return placed

rng = np.random.default_rng(7)
beads = layout(rng, 0.14)                                   # drawn in order: the first ones exist from the first frame
merge = {i for i in range(len(beads)) if rng.random() < 0.12 and beads[i][2] > 3.5}   # these grow a second bead on them: they merge
ang = {i: rng.uniform(0, 2 * np.pi) for i in merge}
SHARE, SCALE = [0.30, 0.50, 0.70, 0.88, 1.0], [0.55, 0.65, 0.78, 0.92, 1.0]
for k in range(5):
    h = np.zeros((N, N), np.float32)
    for i, (x, y, r) in enumerate(beads[:int(len(beads) * SHARE[k])]):
        cap(h, x, y, r * SCALE[k])
        if k >= 3 and i in merge:                           # two beads that ran into each other
            cap(h, x + np.cos(ang[i]) * r * 0.85, y + np.sin(ang[i]) * r * 0.85, r * 0.75 * SCALE[k])
    save(h, 'droplets%d.normal.png' % (k + 1))

# glass: beads, each with a thin run-off streak above it (image up), so scrolling the map downward makes them run
rng = np.random.default_rng(11)
h = np.zeros((N, N), np.float32)
for x, y, r in layout(rng, 0.06):
    cap(h, x, y, r)
for _ in range(70):
    x, y, r, ln = rng.uniform(0, N), rng.uniform(0, N), rng.uniform(2.5, 5), rng.uniform(30, 120)
    cap(h, x, y, r)
    for t in np.arange(0, ln, 1.5):
        cap(h, x, (y - t) % N, max(0.9, r * 0.35 * (1 - t / ln)))
save(h, 'glass.normal.png')
print('wrote', os.path.normpath(OUT))
