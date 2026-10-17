"""Writes mod/art/surfacefx/droplets.normal.png: a seamless 512x512 tangent-space normal map of small beads of water (the one shared texture of the rain effect).
   python tools/gen_droplets.py   (needs numpy, Pillow)"""
import os, numpy as np
from PIL import Image
N, rng = 512, np.random.default_rng(7)
TARGET = 0.12                                   # share of the tile that is a bead: rain on paint is sparse, flat paint in between
h = np.zeros((N, N), np.float32)
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
placed, area, tries = [], 0.0, 0
while area < TARGET * N * N and tries < 20000:
    tries += 1
    r = 1.5 + 5.5 * rng.random() ** 2.5          # many small beads, a few big ones
    cx, cy = rng.uniform(0, N), rng.uniform(0, N)
    if any(min(abs(cx - x), N - abs(cx - x)) ** 2 + min(abs(cy - y), N - abs(cy - y)) ** 2 < (r + q + 1.5) ** 2 for x, y, q in placed):
        continue                                  # beads do not touch (they would have merged)
    placed.append((cx, cy, r)); area += np.pi * r * r
    dx = np.minimum(np.abs(xx - cx), N - np.abs(xx - cx)); dy = np.minimum(np.abs(yy - cy), N - np.abs(yy - cy))
    d2 = (dx * dx + dy * dy) / (r * r)
    h = np.maximum(h, np.where(d2 < 1, (1 - d2) * r, 0))   # smooth round cap, flat outside
print(len(placed), 'beads, coverage', round(area / (N * N), 3))
gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
n = np.dstack([-gx, -gy, np.full_like(h, 1.0)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
img = ((n * 0.5 + 0.5) * 255).astype(np.uint8)
out = os.path.join(os.path.dirname(__file__), '..', 'mod', 'art', 'surfacefx', 'droplets.normal.png')
Image.fromarray(img).save(out)
print('wrote', os.path.normpath(out))
