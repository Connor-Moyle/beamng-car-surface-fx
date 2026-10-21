"""Makes the textures and materials of the glossy leak puddles (our own, procedural):

    python tools/make_fluid_assets.py [--out mod/art/surfacefx/fluids]

puddle_o.data.png: a soft, slightly irregular oval filling POOL of the plane (the edge softness is in the opacity map) inside a faint wet-stain ring that
fades out at the plane's edge, white.color.png: a flat white base, rainbow.color.png and rainbow_o.data.png: the thin-film sheen of oil (faint, wide, slow swirls of muted hue, only
toward the thin edge, none in the thick middle). main.materials.json: one material per fluid, the tint in baseColorFactor (it multiplies the base map), very low roughness so the
surface mirrors the sky like a rain puddle. The textures are cooked to DDS by the game (tools/ingest_cooked_dds.py --dir=mod/art/surfacefx/fluids).
"""
import argparse
import colorsys
import json
import os

import numpy as np
from PIL import Image

N = 256
POOL = 0.72          # the pool's radius as a share of the plane's half-size (fluidmesh.lua scales the plane by 1/POOL); the rest is the wet ring


def grid():
    y, x = np.mgrid[0:N, 0:N]
    u = (x + 0.5) / N * 2 - 1
    v = (y + 0.5) / N * 2 - 1
    return u, v


def smoothstep(a, b, t):
    t = np.clip((t - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def oval():
    u, v = grid()
    d = np.sqrt(u * u + v * v)
    th = np.arctan2(v, u)
    edge = 1 + 0.07 * np.sin(3 * th + 0.6) + 0.04 * np.sin(5 * th + 2.0) + 0.025 * np.sin(8 * th + 4.1)   # an uneven edge: a puddle is never a circle
    dd = d / edge / POOL                                                                      # 1 at the pool's edge
    pool = smoothstep(1.0, 0.7, dd)
    ring = 0.25 * smoothstep(1.0, 0.8, d)                                                     # the concrete wetted round the pool, gone before the plane's edge
    return np.maximum(pool, ring), pool, dd, th


def save_grey(a, path):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), 'L').save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='mod/art/surfacefx/fluids')
    out = ap.parse_args().out
    os.makedirs(out, exist_ok=True)
    mask, pool, dd, th = oval()
    save_grey(mask, os.path.join(out, 'puddle_o.data.png'))
    Image.fromarray(np.full((16, 16, 3), 255, np.uint8), 'RGB').save(os.path.join(out, 'white.color.png'))
    # the sheen: real oil on concrete is a near-black pool with a faint film seen at low angles, in soft wide swirls (a third of the pool across), strongest near the thin edge and
    # none in the thick middle; the pool under it stays dark and glossy
    def noise(seed, beta):
        rng = np.random.default_rng(seed)
        f = np.fft.fft2(rng.standard_normal((N, N)))
        fy, fx = np.meshgrid(np.fft.fftfreq(N), np.fft.fftfreq(N), indexing='ij')
        k = np.sqrt(fx * fx + fy * fy)
        k[0, 0] = 1
        a = np.real(np.fft.ifft2(f / k ** beta))
        return (a - a.mean()) / (a.std() + 1e-9)
    n1, n2, n3 = noise(11, 3.4), noise(23, 3.4), noise(37, 3.2)                      # beta 3.4: the lowest frequencies only, so a swirl spans a good part of the pool
    palette = [0.78, 0.55, 0.09, 0.85, 0.47]               # purple, blue, bronze, magenta, teal
    t = (0.5 + 0.18 * n1 + 0.12 * np.sin(dd * 3 + n2)) % 1.0
    pos = t * len(palette)
    i0 = pos.astype(int) % len(palette)
    i1 = (i0 + 1) % len(palette)
    fr = pos - np.floor(pos)
    hue = np.array(palette)[i0] * (1 - fr) + np.array(palette)[i1] * fr
    cols = np.array([colorsys.hsv_to_rgb(h % 1.0, 0.11, 1.0) for h in np.linspace(0, 1, 256)], np.float32)
    rgb = cols[(hue % 1.0 * 255).astype(int)]
    Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(out, 'rainbow.color.png'))
    wisp = smoothstep(-0.1, 1.0, n2 * 0.6 + n3 * 0.4 + 0.3)                          # slow wisps across the surface
    thin = smoothstep(0.35, 0.95, dd)                                                 # only the thin outer film; the thick middle carries none
    bare = smoothstep(-0.9, 0.4, n1)                                                  # part of the rim carries no colour at all
    save_grey(pool * wisp * thin * bare * 0.6, os.path.join(out, 'rainbow_o.data.png'))

    D = '/art/surfacefx/fluids/'

    def mat(name, tint, opacity, rough=0.03, metal=0.1, base='white.color.png', zwrite=True):
        return {'name': name, 'mapTo': name, 'class': 'Material',
                'Stages': [{'baseColorMap': D + base, 'opacityMap': D + opacity, 'baseColorFactor': tint, 'metallicFactor': metal, 'roughnessFactor': rough}, {}, {}, {}],
                'annotation': 'ASPHALT', 'castShadows': False, 'materialTag0': 'decal', 'materialTag1': 'road', 'materialTag2': 'beamng',
                'translucent': True, 'translucentZWrite': zwrite, 'doubleSided': True, 'version': 1.5}
    mats = [mat('csfx_puddle_oil', [0.03, 0.028, 0.025, 1], 'puddle_o.data.png', 0.02, 0.9),
            # coolant and fuel are clear liquids: a dark tint on the full mask, the gloss from a very smooth surface and only as much metallic as reads wet (a thin 60 % mask at
            # half metallic read as a flat matte disc in the game, 80's close-up 2026-10-21)
            mat('csfx_puddle_coolant', [0.05, 0.30, 0.10, 1], 'puddle_o.data.png', 0.02, 0.6),
            mat('csfx_puddle_fuel', [0.30, 0.24, 0.06, 1], 'puddle_o.data.png', 0.02, 0.6),
            mat('csfx_puddle_sheen', [1, 1, 1, 1], 'rainbow_o.data.png', 0.08, 0.5, 'rainbow.color.png', zwrite=False)]      # the sheen writes no depth: the plane under it must not be hidden by its empty parts
    with open(os.path.join(out, 'main.materials.json'), 'w') as f:
        json.dump({m['name']: m for m in mats}, f, indent=1)
    print('wrote', out)


if __name__ == '__main__':
    main()
