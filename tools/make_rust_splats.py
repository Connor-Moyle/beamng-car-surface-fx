"""The rust splat atlas for the paint canvas, made from REAL CC0 photographs of rust (ambientCG Rust002, Rust004, Rust005, see docs/TEXTURE_CREDITS.md).

    python tools/make_rust_splats.py <raw folder with Rust002/, Rust004/, Rust005/ ...> [out folder]

The raw folder is OUTSIDE the mod (the downloads are untrusted): <raw>/<assetId>/<assetId>_1K-JPG_Color.jpg. Only the colour maps are read.
Writes mod/art/surfacefx/splats/rust.png: an RGBA atlas of 4 x 4 cells of 256 px (16 variants), the layout of the other splat atlases (tools/make_real_splats.py). RGB is the photographed
rust colour (lightly graded), a darker flaking rim round the pit; alpha is a soft, broken-edged pit mask from seeded noise, opaque in the middle and 0 at the cell border, so the same
script and the same downloads give the same picture. Colour only (the paint canvas has no normal or roughness map).
"""
import os, sys, glob
import numpy as np
from PIL import Image

CELL, GRID = 256, 4
RAW = sys.argv[1] if len(sys.argv) > 1 else r'C:\Dev\csfx-textures-raw\rust'
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'mod', 'art', 'surfacefx', 'splats')


def fbm(rng, n, base=3, octaves=4):
    acc = np.zeros((n, n), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        g = max(2, base * 2 ** o)
        a = rng.random((g, g)).astype(np.float32)
        acc += np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC), np.float32) / 255.0 * amp
        tot += amp
        amp *= 0.5
    return acc / tot


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def crop(rng, img, n=CELL):
    h, w, _ = img.shape
    s = int(rng.integers(n, min(h, w) + 1))
    y, x = int(rng.integers(0, h - s + 1)), int(rng.integers(0, w - s + 1))
    c = Image.fromarray((img[y:y + s, x:x + s] * 255).astype(np.uint8)).resize((n, n), Image.LANCZOS)
    return np.asarray(c, np.float32) / 255.0


def radial(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return np.sqrt(((x - n / 2) / (n / 2)) ** 2 + ((y - n / 2) / (n / 2)) ** 2)


def rust_cell(rng, img):
    r = radial(CELL)
    n = fbm(rng, CELL, 4, 5)
    pit = smooth(n * 0.95 + (1 - r ** 1.3) * 0.7 - 0.62, 0.0, 0.1)                     # a rough pit with a broken edge
    spots = smooth(fbm(rng, CELL, 9, 3) + (1 - r) * 0.3, 0.72, 0.8) * smooth(n, 0.3, 0.6)   # satellite pinpricks round it
    a = np.clip(np.maximum(pit, spots * 0.9), 0, 1) * (1 - smooth(r, 0.86, 0.98))      # 0 at the cell border
    rim = np.clip(1 - smooth(pit, 0.0, 0.55), 0, 1)[..., None]                           # darker, flaking rim where it is thin
    c = crop(rng, img)
    lum = (c @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
    c = np.clip(c * 0.8 + np.array([0.46, 0.2, 0.08], np.float32) * np.clip(lum / max(float(lum.mean()), 1e-3), 0.4, 1.6) * 0.2, 0, 1)
    c = c * (1 - 0.45 * rim)
    return np.dstack([np.clip(c, 0, 1), a])


def main():
    maps = sorted(glob.glob(os.path.join(RAW, '*', '*_Color.jpg')))
    if not maps:
        sys.exit('no textures in ' + RAW)
    imgs = [np.asarray(Image.open(m).convert('RGB'), np.float32) / 255.0 for m in maps]
    rng = np.random.default_rng(77)
    im = Image.new('RGBA', (CELL * GRID, CELL * GRID))
    for i in range(GRID * GRID):
        c = rust_cell(rng, imgs[i % len(imgs)])
        u = (np.clip(c, 0, 1) * 255).astype(np.uint8)
        u[..., :3] &= 0xF8                                  # 5 bits of colour: the file stays small (the canvas only multiplies and blends it)
        u[u[..., 3] == 0, :3] = 0                           # nothing hidden in transparent pixels
        im.paste(Image.fromarray(u, 'RGBA'), ((i % GRID) * CELL, (i // GRID) * CELL))
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, 'rust.png')
    im.save(p, optimize=True)
    print(p, os.path.getsize(p) // 1024, 'KB, from', len(maps), 'textures')


main()
