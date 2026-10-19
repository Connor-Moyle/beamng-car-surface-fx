"""Splat atlases for the paint canvas, made from REAL CC0 photographs of mud, dirt, dust and snow (ambientCG, see docs/TEXTURE_CREDITS.md).

    python tools/make_real_splats.py <raw folder with mud/ dirt/ snow/ ...> [out folder]

The raw folder is OUTSIDE the mod (the downloads are untrusted): <raw>/<type>/<assetId>/<assetId>_1K-JPG_Color.jpg. Only the colour maps are read.
Writes mod/art/surfacefx/splats/{mud,dust,snow}.png: RGBA atlases of 4 x 4 cells of 256 px (16 variants each). RGB is the real texture's colour (graded), alpha is a soft splat
mask made from seeded noise, so the same script and the same downloads give the same pictures. The page (carSurfaceFx scratch.js) picks a variant and a rotation per splat.
The paint canvas has only a colour map, so there is no normal or roughness map for these: the PBR maps of the same photos are used by the ground decals, not by the canvas.
"""
import os, sys, glob
import numpy as np
from PIL import Image, ImageFilter

CELL, GRID = 256, 4
RAW = sys.argv[1] if len(sys.argv) > 1 else r'C:\Dev\csfx-textures-raw'
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'mod', 'art', 'surfacefx', 'splats')


def colour_maps(kind_dirs):
    out = []
    for d in kind_dirs:
        out += sorted(glob.glob(os.path.join(RAW, d, '*', '*_Color.jpg')))
    return out


def load(path):
    return np.asarray(Image.open(path).convert('RGB'), dtype=np.float32) / 255.0


def fbm(rng, n, base=3, octaves=4):
    """smooth noise 0..1, n x n"""
    acc = np.zeros((n, n), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        g = max(2, base * 2 ** o)
        a = rng.random((g, g)).astype(np.float32)
        im = Image.fromarray((a * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
        acc += np.asarray(im, np.float32) / 255.0 * amp
        tot += amp
        amp *= 0.5
    return acc / tot


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def crop(rng, img, n=CELL):
    h, w, _ = img.shape
    s = int(rng.integers(n, min(h, w) + 1))            # a crop of random scale, resized to a cell
    y, x = int(rng.integers(0, h - s + 1)), int(rng.integers(0, w - s + 1))
    c = Image.fromarray((img[y:y + s, x:x + s] * 255).astype(np.uint8)).resize((n, n), Image.LANCZOS)
    return np.asarray(c, np.float32) / 255.0


def grade(c, target, mix, light=1.0):
    """pull the colour of a crop toward a target colour, keeping its own light and dark variation"""
    lum = (c @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
    mean = max(float(lum.mean()), 1e-3)
    shade = np.clip(lum / mean, 0.35, 1.8)
    tinted = np.array(target, np.float32)[None, None, :] * shade * light
    return np.clip(c * (1 - mix) + tinted * mix, 0, 1)


def radial(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    return np.sqrt(((x - n / 2) / (n / 2)) ** 2 + ((y - n / 2) / (n / 2)) ** 2)


def droplets(rng, n, count, rmin, rmax, ring=(0.5, 0.95)):
    m = np.zeros((n, n), np.float32)
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    for _ in range(count):
        a, d = rng.random() * 6.2832, rng.uniform(*ring) * n / 2
        cx, cy = n / 2 + np.cos(a) * d, n / 2 + np.sin(a) * d
        r = rng.uniform(rmin, rmax)
        m = np.maximum(m, 1 - smooth(np.sqrt((x - cx) ** 2 + (y - cy) ** 2), r * 0.5, r))
    return m


def mud_cell(rng, img):
    r = radial(CELL)
    n = fbm(rng, CELL, 3, 5)
    body = smooth(n * 0.9 + (1 - r ** 1.4) * 0.75 - 0.55, 0.0, 0.14)          # a lumpy blob with a soft broken edge
    drops = droplets(rng, CELL, int(rng.integers(10, 22)), 2, 7) * smooth(n, 0.25, 0.6)
    a = np.clip(np.maximum(body, drops), 0, 1)
    edge = np.clip(1 - smooth(body, 0.0, 0.6), 0, 1)[..., None]                # a darker rim where it is thin
    c = grade(crop(rng, img), (0.40, 0.28, 0.18), 0.55, 0.9) * (1 - 0.3 * edge)
    return np.dstack([np.clip(c, 0, 1), a])


def dust_cell(rng, img):
    r = radial(CELL)
    n = fbm(rng, CELL, 2, 5)
    grain = rng.random((CELL, CELL)).astype(np.float32)
    a = smooth(1 - r, 0.0, 0.85) * (0.35 + 0.65 * n) * (0.8 + 0.2 * grain)      # a soft powder patch, no edge
    a = np.clip(a * 1.1, 0, 1)
    c = grade(crop(rng, img), (0.66, 0.57, 0.43), 0.8, 1.0)
    return np.dstack([c, a])


def snow_cell(rng, img):
    r = radial(CELL)
    n = fbm(rng, CELL, 3, 5)
    body = smooth(n * 0.8 + (1 - r ** 1.6) * 0.9 - 0.45, 0.0, 0.25)             # a drift: soft, fairly opaque
    sparkle = droplets(rng, CELL, int(rng.integers(8, 16)), 2, 5, (0.3, 0.9)) * 0.7 * smooth(n, 0.3, 0.7)
    a = np.clip(np.maximum(body, sparkle), 0, 1)
    c = grade(crop(rng, img), (0.93, 0.95, 0.99), 0.75, 1.0)
    return np.dstack([c, a])


def atlas(name, cells):
    im = Image.new('RGBA', (CELL * GRID, CELL * GRID))
    for i, c in enumerate(cells):
        im.paste(Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8), 'RGBA'), ((i % GRID) * CELL, (i // GRID) * CELL))
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name + '.png')
    im.save(p, optimize=True)
    print(p, os.path.getsize(p) // 1024, 'KB')


def main():
    jobs = {'mud': (['mud'], mud_cell, 11), 'dust': (['dirt'], dust_cell, 22), 'snow': (['snow'], snow_cell, 33)}
    for name, (dirs, fn, seed) in jobs.items():
        maps = colour_maps(dirs)
        if not maps:
            print('no textures for', name, 'in', RAW)
            continue
        imgs = [load(m) for m in maps]
        if name == 'snow':                                                       # wet snow with the ground showing through is not a snow splat
            imgs = [i for i in imgs if np.percentile(i @ np.array([0.2126, 0.7152, 0.0722], np.float32), 12) > 0.6]
            print('clean snow textures:', len(imgs))
        rng = np.random.default_rng(seed)
        cells = [fn(rng, imgs[i % len(imgs)]) for i in range(GRID * GRID)]       # every source texture is used, round and round
        atlas(name, cells)
        print(name, 'from', len(maps), 'textures')


main()
