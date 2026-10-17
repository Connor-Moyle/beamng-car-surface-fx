"""Writes mod/art/surfacefx/droplets.normal.png: a seamless 512x512 tangent-space normal map of small beads of water (the one shared texture of the rain effect).
   python tools/gen_droplets.py   (needs numpy, Pillow)"""
import os, numpy as np
from PIL import Image
N, rng = 512, np.random.default_rng(7)
h = np.zeros((N, N), np.float32)
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
for _ in range(900):
    cx, cy, r = rng.uniform(0, N), rng.uniform(0, N), rng.uniform(2.5, 9) ** 1.0
    dx = np.minimum(np.abs(xx - cx), N - np.abs(xx - cx)); dy = np.minimum(np.abs(yy - cy), N - np.abs(yy - cy))
    d2 = (dx * dx + dy * dy) / (r * r)
    h = np.maximum(h, np.where(d2 < 1, np.sqrt(np.clip(1 - d2, 0, 1)) * r, 0))
gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
n = np.dstack([-gx, -gy, np.full_like(h, 1.0)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
img = ((n * 0.5 + 0.5) * 255).astype(np.uint8)
out = os.path.join(os.path.dirname(__file__), '..', 'mod', 'art', 'surfacefx', 'droplets.normal.png')
Image.fromarray(img).save(out)
print('wrote', os.path.normpath(out))
