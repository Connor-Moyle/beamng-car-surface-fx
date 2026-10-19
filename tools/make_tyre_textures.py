"""Tyre tread textures, made here (no photos, no downloaded tread): python make_tyre_textures.py [out folder]
Five tread patterns x four wear stages (new, half, worn, belts) as tileable 1024 x 1024 maps, plus one damage overlay.
  <pattern>_<stage>_n.png   normal map, OpenGL (green up), tileable round the tyre
  <pattern>_<stage>_r.png   roughness, 8-bit grey (1 = rough)
  <pattern>_<stage>_ao.png  occlusion / cavity, 8-bit grey (grooves dark), for the colour or AO slot
  damage_n.png / damage_r.png  gouges, cuts and a blister, to lay over any of them
The texture runs: V (rows) round the circumference, U (columns) across the tread. Everything is periodic in both, so the strip tiles round the tyre.
Parameters: SIZE, STRIP_M (the width of the strip in metres: sets how big the pattern is), UV_SWAP (set if the tyre's UV runs the other way), NORMAL_FLIP_Y (DirectX green down).
The rubber grain (roughness and a little normal) is from ambientCG Rubber001, Rubber002 and Rubber004 (CC0), read from ../rubber/ when present.
"""
import os
import sys

import numpy as np
from PIL import Image

SIZE = 1024
STRIP_M = 0.24                 # across the tread, as one texture
UV_SWAP = False
NORMAL_FLIP_Y = False
HERE = os.path.dirname(os.path.abspath(__file__))
RUBBER = os.path.join(HERE, '..', 'rubber')
S = np.float32


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def fnoise(seed, cells, size=SIZE):
    """periodic value noise (a few octaves) in 0..1: made in the Fourier domain so that it tiles"""
    rng = np.random.default_rng(seed)
    f = np.fft.fftfreq(size)[:, None] ** 2 + np.fft.fftfreq(size)[None, :] ** 2
    k = np.sqrt(f) * size / max(cells, 1)
    spec = (rng.normal(size=(size, size)) + 1j * rng.normal(size=(size, size))) * np.exp(-k ** 2 * 0.5) / (1 + k) ** 0.8
    spec[0, 0] = 0
    a = np.fft.ifft2(spec).real
    a = (a - a.min()) / (a.max() - a.min() + 1e-9)
    return a.astype(S)


def grid():
    v = (np.arange(SIZE, dtype=S) + 0.5) / SIZE
    return np.meshgrid(v, v)          # U across (columns), V round (rows)


def band(x, c, w, soft):
    """1 inside a band of width w round c, periodic in 0..1, soft edge"""
    d = np.abs(((x - c + 0.5) % 1.0) - 0.5)
    return 1 - smooth(d, w / 2 - soft, w / 2 + soft)


def groove(pattern):
    """groove mask 0..1 (1 = groove) and sipe mask (thin cuts) for each pattern"""
    U, V = grid()
    soft = 0.004
    sipe = np.zeros_like(U)
    if pattern == 'rib':
        g = np.zeros_like(U)
        for c in (0.2, 0.4, 0.6, 0.8):
            g = np.maximum(g, band(U, c, 0.05, soft))
        for k in range(24):
            sipe = np.maximum(sipe, band(V + 0.3 * np.round(U * 5), k / 24, 0.006, 0.002) * (np.abs((U * 5) % 1 - 0.5) < 0.42))
    elif pattern == 'directional':
        n = 12
        arm = np.abs(U - 0.5) * 2                          # 0 at the centre
        g = band((V * n + arm * 2.2) % 1.0, 0.5, 0.26, 0.04) * smooth(arm, 0.05, 0.12) * (arm < 0.93)
        g = np.maximum(g, band(U, 0.5, 0.025, soft) * 0.7)
        sipe = band((V * n + arm * 2.2 + 0.5) % 1.0, 0.5, 0.05, 0.015) * smooth(arm, 0.2, 0.3) * (arm < 0.85)
    elif pattern == 'block':
        n = 9
        col = np.floor(U * 4)
        g = np.maximum.reduce([band(U, c, 0.045, soft) for c in (0.25, 0.5, 0.75)])
        lat = band((V * n + col * 0.31) % 1.0, 0.5, 0.20, 0.03) * (0.3 + 0.7 * (np.abs(U - 0.5) > 0.0))
        g = np.maximum(g, lat)
    elif pattern == 'winter':
        n = 15
        col = np.floor(U * 5)
        g = np.maximum.reduce([band(U, c, 0.035, soft) for c in (0.2, 0.4, 0.6, 0.8)])
        g = np.maximum(g, band((V * n + col * 0.37) % 1.0, 0.5, 0.17, 0.03))
        z = (np.abs(((U * 5) % 1.0) - 0.5) * 2)
        for k in (0.2, 0.5, 0.8):
            sipe = np.maximum(sipe, band((V * n + col * 0.37 + 0.12 * np.sin(U * 5 * 2 * np.pi * 3)) % 1.0, k * 0.5 + 0.25 - 0.15 + 0.05 * k, 0.012, 0.004) * (z < 0.8))
    elif pattern == 'offroad':
        n = 5
        col = np.floor(U * 3)
        g = band((V * n + col * 0.5) % 1.0, 0.5, 0.38, 0.05)
        g = np.maximum(g, np.maximum.reduce([band(U, c, 0.07, soft) for c in (1 / 3, 2 / 3)]) * 0.9)
    else:
        raise ValueError(pattern)
    return np.clip(g, 0, 1), np.clip(sipe, 0, 1)


STAGES = {            # groove depth kept (1 = new), polish, belts showing, belt wear scale
    'new': dict(depth=1.0, polish=0.0, belts=0.0),
    'half': dict(depth=0.55, polish=0.35, belts=0.0),
    'worn': dict(depth=0.18, polish=0.7, belts=0.12),
    'belts': dict(depth=0.06, polish=1.0, belts=0.85),
}
PATTERNS = ('rib', 'directional', 'block', 'winter', 'offroad')


def rubber_grain(seed):
    """the real rubber grain: a ambientCG rubber roughness map (tiled), as a zero-mean 0..1 field; the procedural noise when the folder is missing"""
    names = ['Rubber001', 'Rubber002', 'Rubber004']
    p = os.path.join(RUBBER, names[seed % 3], '%s_1K-JPG_Roughness.jpg' % names[seed % 3])
    if os.path.exists(p):
        a = np.asarray(Image.open(p).convert('L').resize((SIZE, SIZE), Image.BICUBIC), S) / 255
        return a, names[seed % 3]
    return fnoise(100 + seed, 120), None


def height_and_rough(pattern, stage, seed):
    st = STAGES[stage]
    g, sipe = groove(pattern)
    n_big, n_mid = fnoise(seed, 3), fnoise(seed + 1, 14)
    grain, _ = rubber_grain(seed)
    # tread wear is uneven: more at the centre and one shoulder, more where the noise says
    U, V = grid()
    uneven = np.clip(0.5 * (1 - np.abs(U - 0.5) * 1.4) + 0.5 * n_big + 0.15 * (U - 0.5), 0, 1)
    depth = np.clip(st['depth'] + (st['depth'] < 0.9) * (0.5 - uneven) * 0.35, 0.0, 1.0)
    h = 1 - g * depth - sipe * 0.5 * depth * (1 - g)
    # land: moulding flash and small ripples when new; worn smooth when polished
    ripple = (grain - 0.5) * 0.05 + (n_mid - 0.5) * 0.04
    h = h + ripple * (1 - 0.8 * st['polish'])
    rough = 0.9 - 0.05 * g + (grain - 0.5) * 0.30 * (1 - 0.5 * st['polish']) - 0.22 * st['polish']
    # the belts: bald where the wear noise is high; cord weave under it
    cord = np.zeros_like(h)
    if st['belts'] > 0:
        wear = smooth(uneven + 0.25 * (fnoise(seed + 2, 6) - 0.5), 1.0 - st['belts'] * 0.75, 1.0 - st['belts'] * 0.75 + 0.12)
        weave = 0.5 + 0.25 * np.sin(2 * np.pi * 60 * (U + V)) + 0.25 * np.sin(2 * np.pi * 60 * (U - V))     # two crossing sets of cords
        cord = wear * (0.06 * weave + 0.03)
        h = h * (1 - wear * 0.6) + wear * 0.35 + cord           # the cords sit a bit below the rubber, with the weave on top
        rough = rough * (1 - wear) + wear * (0.55 + 0.15 * (weave - 0.5))
        g = np.clip(g * (1 - wear), 0, 1)
    return h.astype(S), np.clip(rough, 0.2, 1).astype(S), g.astype(S)


def normal_from_height(h, strength):
    """tileable normal (OpenGL, green up): the gradient round the edges wraps"""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    if UV_SWAP:
        gx, gy = gy, gx
    nx, ny = -gx * strength, gy * strength                          # image y grows downward, so green up needs +gy
    if NORMAL_FLIP_Y:
        ny = -ny
    n = np.stack([nx, ny, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save_rgb(a, path):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path, optimize=True)


def damage(seed=7):
    """gouges, a cut and a blister on a neutral tread: a normal and a roughness to lay over a tyre"""
    rng = np.random.default_rng(seed)
    U, V = grid()
    h = np.zeros_like(U)
    for _ in range(9):                                              # gouges: short, slightly curved, uneven depth
        cu, cv, ang, ln, w = rng.random(), rng.random(), rng.uniform(0, np.pi), rng.uniform(0.04, 0.12), rng.uniform(0.004, 0.012)
        du = ((U - cu + 0.5) % 1) - 0.5
        dv = ((V - cv + 0.5) % 1) - 0.5
        a = du * np.cos(ang) + dv * np.sin(ang)
        b = -du * np.sin(ang) + dv * np.cos(ang) + 0.01 * np.sin(a * 40)
        h -= np.exp(-(b / w) ** 2) * smooth(ln - np.abs(a), 0, 0.02) * rng.uniform(0.4, 1.0)
    for _ in range(2):                                              # blisters / bulges
        cu, cv, r = rng.random(), rng.random(), rng.uniform(0.03, 0.06)
        du = ((U - cu + 0.5) % 1) - 0.5
        dv = ((V - cv + 0.5) % 1) - 0.5
        d2 = (du ** 2 + dv ** 2) / r ** 2
        h += np.exp(-d2 * 2.0) * 0.8 - np.exp(-((np.sqrt(d2) - 1.15) / 0.18) ** 2) * 0.35
    rough = 0.9 - 0.25 * smooth(-h, 0.2, 0.7)
    return h.astype(S), rough.astype(S)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'out')
    os.makedirs(out, exist_ok=True)
    for pi, pattern in enumerate(PATTERNS):
        for stage in STAGES:
            h, rough, g = height_and_rough(pattern, stage, 10 + pi)
            save_rgb(normal_from_height(h, 5.0), os.path.join(out, '%s_%s_n.png' % (pattern, stage)))
            Image.fromarray((np.clip(rough, 0, 1) * 255 + 0.5).astype(np.uint8), 'L').save(os.path.join(out, '%s_%s_r.png' % (pattern, stage)), optimize=True)
            ao = np.clip(0.35 + 0.65 * (h - h.min()) / (h.max() - h.min() + 1e-9), 0, 1)
            Image.fromarray((ao * 255 + 0.5).astype(np.uint8), 'L').save(os.path.join(out, '%s_%s_ao.png' % (pattern, stage)), optimize=True)
            print(pattern, stage)
    dh, dr = damage()
    save_rgb(normal_from_height(dh, 6.0), os.path.join(out, 'damage_n.png'))
    Image.fromarray((np.clip(dr, 0, 1) * 255 + 0.5).astype(np.uint8), 'L').save(os.path.join(out, 'damage_r.png'), optimize=True)
    # a contact sheet: shaded (a light from the upper left) height of each pattern at each stage, 256 px
    sheet = Image.new('L', (256 * 4, 256 * len(PATTERNS)))
    for pi, pattern in enumerate(PATTERNS):
        for si, stage in enumerate(STAGES):
            n = np.asarray(Image.open(os.path.join(out, '%s_%s_n.png' % (pattern, stage))), S) / 255 * 2 - 1
            lit = np.clip(0.55 + 0.45 * (n[..., 0] * -0.5 + n[..., 1] * 0.5) * 2.2, 0, 1)
            sheet.paste(Image.fromarray((lit * 255).astype(np.uint8), 'L').resize((256, 256), Image.LANCZOS), (si * 256, pi * 256))
    sheet.save(os.path.join(out, 'sheet.png'))
    print('wrote', out)


if __name__ == '__main__':
    main()
