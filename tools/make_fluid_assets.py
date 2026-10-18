"""Makes the textures and materials of the glossy leak puddles (our own, procedural):

    python tools/make_fluid_assets.py [--out mod/art/surfacefx/fluids]

puddle_o.data.png / puddle_o_thin.data.png: a soft, slightly irregular oval (the edge softness is in the opacity map), white.color.png: a flat white base, rainbow.color.png and
rainbow_o.data.png: the thin-film sheen of oil (hue bands that swirl, strongest toward the edge). main.materials.json: one material per fluid, the tint in baseColorFactor
(it multiplies the base map), very low roughness so the surface mirrors the sky like a rain puddle.
"""
import argparse
import colorsys
import json
import os

import numpy as np
from PIL import Image

N = 256


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
    dd = d / edge
    return smoothstep(1.0, 0.7, dd), dd, th


def save_grey(a, path):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), 'L').save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='mod/art/surfacefx/fluids')
    out = ap.parse_args().out
    os.makedirs(out, exist_ok=True)
    mask, dd, th = oval()
    save_grey(mask, os.path.join(out, 'puddle_o.data.png'))
    save_grey(mask * 0.6, os.path.join(out, 'puddle_o_thin.data.png'))
    Image.fromarray(np.full((16, 16, 3), 255, np.uint8), 'RGB').save(os.path.join(out, 'white.color.png'))
    # the sheen: hue bands round the puddle that wander with the angle (a thin film is a ramp of colours with its thickness), strongest in the outer half
    rng = np.random.default_rng(7)
    ph = rng.uniform(0, 6.283, 4)
    hue = (dd * 2.3 + 0.12 * np.sin(2 * th + ph[0]) + 0.08 * np.sin(5 * th + ph[1]) + 0.1 * np.sin(dd * 9 + ph[2])) % 1.0
    rgb = np.zeros((N, N, 3), np.float32)
    flat = hue.reshape(-1)
    cols = np.array([colorsys.hsv_to_rgb(h, 0.55, 1.0) for h in np.linspace(0, 1, 256)], np.float32)
    rgb = cols[(flat * 255).astype(int)].reshape(N, N, 3)
    Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(out, 'rainbow.color.png'))
    band = 0.55 + 0.45 * np.sin(dd * 14 + ph[3]) ** 2
    save_grey(mask * smoothstep(0.2, 0.9, dd) * band * 0.45, os.path.join(out, 'rainbow_o.data.png'))

    D = '/art/surfacefx/fluids/'

    def mat(name, tint, opacity, rough=0.03, metal=0.1, base='white.color.png', zwrite=True):
        return {'name': name, 'mapTo': name, 'class': 'Material',
                'Stages': [{'baseColorMap': D + base, 'opacityMap': D + opacity, 'baseColorFactor': tint, 'metallicFactor': metal, 'roughnessFactor': rough}, {}, {}, {}],
                'annotation': 'ASPHALT', 'castShadows': False, 'materialTag0': 'decal', 'materialTag1': 'road', 'materialTag2': 'beamng',
                'translucent': True, 'translucentZWrite': zwrite, 'doubleSided': True, 'version': 1.5}
    mats = [mat('csfx_puddle_oil', [0.03, 0.028, 0.025, 1], 'puddle_o.data.png', 0.02, 0.9),
            mat('csfx_puddle_coolant', [0.10, 0.50, 0.18, 1], 'puddle_o_thin.data.png', 0.03, 0.5),
            mat('csfx_puddle_fuel', [0.55, 0.44, 0.10, 1], 'puddle_o_thin.data.png', 0.04, 0.5),
            mat('csfx_puddle_sheen', [1, 1, 1, 1], 'rainbow_o.data.png', 0.08, 0.5, 'rainbow.color.png', zwrite=False)]      # the sheen writes no depth: the plane under it must not be hidden by its empty parts
    with open(os.path.join(out, 'main.materials.json'), 'w') as f:
        json.dump({m['name']: m for m in mats}, f, indent=1)
    print('wrote', out)


if __name__ == '__main__':
    main()
