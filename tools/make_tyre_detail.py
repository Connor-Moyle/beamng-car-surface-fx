"""Plain-rubber detail maps for the tyre wear stages (no tread pattern; the car's own tread stays underneath): python make_tyre_detail.py [out folder]
  worn_1..3, belts_1..3, blown_1..2: <name>_n.png (normal, OpenGL green up, flat = 128,128,255) and <name>_r.png (roughness)
Tileable in both directions, 1024. worn: fine cracks, small chips, smooth lighter rubber. belts: the cord weave with cracks and chips, rough. blown: a torn chunk, a blister and cords showing in the hole.
"""
import os
import sys

import numpy as np
from PIL import Image

from make_tyre_textures import SIZE, S, smooth, fnoise, grid, normal_from_height, save_rgb, rubber_grain


def cracks(seed, cells, width, cover):
    """thin dark cracks: the zero crossings of a periodic noise, only where a second, coarser noise lets them through"""
    n = fnoise(seed, cells)
    line = 1 - smooth(np.abs(n - 0.5), 0.0, width)
    allow = smooth(fnoise(seed + 50, 3), 1 - cover - 0.1, 1 - cover + 0.1)
    return line * allow


def chips(seed, count, size):
    """small chips: a dent with a raised rim at random places (wrapping)"""
    rng = np.random.default_rng(seed)
    U, V = grid()
    h = np.zeros_like(U)
    for _ in range(count):
        cu, cv, r = rng.random(), rng.random(), size * rng.uniform(0.5, 1.6)
        du = ((U - cu + 0.5) % 1) - 0.5
        dv = ((V - cv + 0.5) % 1) - 0.5
        d = np.sqrt(du ** 2 + dv ** 2 * rng.uniform(0.6, 1.4)) / r
        h += -np.exp(-d ** 2 * 3) * rng.uniform(0.5, 1.0) + np.exp(-((d - 1.1) / 0.25) ** 2) * 0.25
    return h.astype(S)


def weave(seed, density, twist):
    """two crossing sets of cords, each cord a twisted rope: height 0..1"""
    U, V = grid()
    wob = (fnoise(seed, 5) - 0.5) * 0.02
    a = (U + V + wob) * density
    b = (U - V + wob) * density
    ca = 0.5 + 0.5 * np.sin(2 * np.pi * a + twist * np.sin(2 * np.pi * b))
    cb = 0.5 + 0.5 * np.sin(2 * np.pi * b + twist * np.sin(2 * np.pi * a))
    return np.maximum(ca, cb).astype(S)


def worn(i):
    seed = 200 + i
    grain, _ = rubber_grain(i)
    h = (grain - 0.5) * 0.05 + (fnoise(seed, 30) - 0.5) * 0.03
    h -= cracks(seed + 1, 40 + 25 * i, 0.012, 0.45 + 0.15 * i) * 0.5
    h -= cracks(seed + 2, 9 + 4 * i, 0.02, 0.25) * 0.25
    h += chips(seed + 3, 14 + 6 * i, 0.012) * 0.4
    rough = 0.62 + (grain - 0.5) * 0.18 + (fnoise(seed + 4, 6) - 0.5) * 0.12 + cracks(seed + 1, 40 + 25 * i, 0.012, 0.45 + 0.15 * i) * 0.25
    return h, rough


def belts(i):
    seed = 300 + i
    grain, _ = rubber_grain(i + 1)
    w = weave(seed, (36, 48, 60)[i], (0.8, 1.2, 1.6)[i])
    fray = smooth(fnoise(seed + 1, 18), 0.55, 0.8)                  # loose, raised cords here and there
    h = w * (0.22 + 0.10 * fray) + (grain - 0.5) * 0.03
    h -= cracks(seed + 2, 12, 0.02, 0.3 + 0.1 * i) * 0.25
    h += chips(seed + 3, 10 + 5 * i, 0.012) * 0.3
    rough = 0.82 + (w - 0.5) * 0.18 + (grain - 0.5) * 0.12 - fray * 0.1
    return h, rough


def blown(i):
    seed = 400 + i
    grain, _ = rubber_grain(i + 2)
    n = fnoise(seed, 3 + i)
    hole = smooth(n, 0.62, 0.68)                                      # a torn-out chunk with an irregular edge
    rim = np.exp(-(((n - 0.62) / 0.025) ** 2))
    cord = weave(seed + 1, 40, 1.2)
    blister = np.exp(-((((fnoise(seed + 2, 4) - 0.8) / 0.08)) ** 2)) * (1 - hole)
    h = (grain - 0.5) * 0.04 - cracks(seed + 3, 30, 0.015, 0.6) * 0.3
    h = h * (1 - hole) + hole * (-0.45 + cord * 0.2) + rim * 0.25 + blister * 0.35
    h += (fnoise(seed + 4, 60) - 0.5) * 0.04 * hole
    rough = 0.72 + (grain - 0.5) * 0.15 + hole * (0.2 + (cord - 0.5) * 0.15) - rim * 0.1
    return h, rough


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out2')
    os.makedirs(out, exist_ok=True)
    sheet = Image.new('L', (256 * 8, 256))
    k = 0
    for kind, fn, count, strength in (('worn', worn, 3, 7.0), ('belts', belts, 3, 5.0), ('blown', blown, 2, 4.0)):
        for i in range(count):
            h, rough = fn(i)
            name = '%s_%d' % (kind, i + 1)
            nm = normal_from_height(h.astype(S), strength)
            save_rgb(nm, os.path.join(out, name + '_n.png'))
            Image.fromarray((np.clip(rough, 0.15, 1) * 255 + 0.5).astype(np.uint8), 'L').save(os.path.join(out, name + '_r.png'), optimize=True)
            lit = np.clip(0.55 + (nm[..., 0] * 2 - 1) * -0.6 + (nm[..., 1] * 2 - 1) * 0.6, 0, 1)
            sheet.paste(Image.fromarray((lit * 255).astype(np.uint8), 'L').resize((256, 256), Image.LANCZOS), (k * 256, 0))
            k += 1
            print(name)
    sheet.crop((0, 0, 256 * k, 256)).save(os.path.join(out, 'sheet.png'))
    print('wrote', out)


if __name__ == '__main__':
    main()
