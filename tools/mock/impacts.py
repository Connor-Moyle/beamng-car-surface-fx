"""Mock-up of the raindrop impact rings at real size (the formulas of scratch.js and glass.js): python tools/mock/impacts.py [out.png]
Rows: paint (a 0.7 px ring opening to 2.6 px, alpha 0.34 to 0.04 over 0.3 s, shown at 4 frames of 90 ms), glass on a dark and a light pane (a white ring 1 to 4 px, alpha 0.4 / 0.22 emissive over 0.25 s, 4 frames of 70 ms).
"""
import sys

import numpy as np
from PIL import Image

SS, ZOOM, CELL = 8, 6, 24


def ring(img, cx, cy, r, w, col, a):
    h, wd = img.shape[:2]
    ys, xs = np.mgrid[0:h, 0:wd]
    d = np.sqrt((xs + 0.5 - cx * SS) ** 2 + (ys + 0.5 - cy * SS) ** 2)
    m = np.clip(1 - np.abs(d - r * SS) / (w * SS / 2 + 0.5), 0, 1) * a
    img[:] = img * (1 - m[..., None]) + np.array(col, np.float32) * m[..., None]


def cell(bg, frame, kind):
    img = np.empty((CELL * SS, CELL * SS, 3), np.float32)
    img[:] = np.array(bg, np.float32) / 255
    if kind == 'paint':
        ph = frame * 0.09 / 0.3
        ring(img, CELL / 2, CELL / 2, 0.7 + 1.9 * ph, 0.7, (0, 0, 0), 0.30 * (1 - ph) + 0.04)
    else:
        ph = frame * 0.07 / 0.25
        ring(img, CELL / 2, CELL / 2, 1 + 3 * ph, 0.8, (1, 1, 1), (0.22 if kind == 'em' else 0.4) * (1 - ph))
    return img.reshape(CELL, SS, CELL, SS, 3).mean(axis=(1, 3))


rows = [('paint, red', (170, 30, 30), 'paint'), ('paint, white', (235, 235, 235), 'paint'), ('glass dark', (36, 48, 54), 'glass'), ('glass light', (188, 204, 212), 'glass'), ('glass emissive', (0, 0, 0), 'em')]
sheet = np.zeros((len(rows) * CELL, 4 * CELL, 3), np.float32)
for r, (_, bg, kind) in enumerate(rows):
    for f in range(4):
        sheet[r * CELL:(r + 1) * CELL, f * CELL:(f + 1) * CELL] = cell(bg, f, kind)
out = sys.argv[1] if len(sys.argv) > 1 else 'impacts.png'
Image.fromarray((np.clip(sheet, 0, 1) ** 0.5 * 255).astype(np.uint8)).resize((4 * CELL * ZOOM, len(rows) * CELL * ZOOM), Image.NEAREST).save(out)
print('wrote', out)
