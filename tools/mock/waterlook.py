"""Mock-ups of rain drops on car paint at real scale: python tools/mock/waterlook.py [out.png]

A panel of a car's body, 1 m x 0.7 m, 1 texel of the paint canvas = 5 mm (the node map of the paint canvas gives about 0.2 texture units per metre of a 1024 canvas), drawn at
4x. Three looks of the same drops on a red, a white and a dark blue paint, lit by a low sun from the upper left and a bright sky:
  A  now: dark discs of 3 to 6 texels radius painted into the base colour map (a multiply map: it can only darken)
  B  multiply only, real size: sub-texel to 1.5 texel drops, a thin dark rim and no body
  D  thin rim and a glint: a transparent body, a thin dark rim (multiply) and a bright glint (the palette is punched and the base map painted light there, as scratches are drawn)
  (a lit normal-map drop is not possible: the engine does not resolve a canvas tag in the normal slot)
Not the game's renderer: a simple clear-coat model (diffuse paint + a sun specular lobe + the sky reflected where a normal tilts up), to compare looks and sizes.
"""
import sys

import numpy as np
from PIL import Image, ImageDraw

S = 4                               # px per texel
W, H = 200, 140                     # texels (1 m x 0.7 m at 5 mm)
rng = np.random.default_rng(5)

PAINTS = {'red': (0.55, 0.04, 0.04), 'white': (0.80, 0.80, 0.78), 'dark blue': (0.03, 0.05, 0.14)}
SUN = np.array([-0.55, -0.45, 0.70])
SUN = SUN / np.linalg.norm(SUN)


def drops(n, rmin, rmax, seed):
    r = np.random.default_rng(seed)
    out = []
    for _ in range(n):
        q = r.random()
        out.append((r.random() * W, r.random() * H, rmin + (rmax - rmin) * q * q))
    return out


def grid():
    y, x = np.mgrid[0:H * S, 0:W * S]
    return (x + 0.5) / S, (y + 0.5) / S


def shade(albedo, nx, ny, nz, wetdark=1.0):
    """clear-coated paint: diffuse + sun specular + the sky reflected (brighter where the normal leans up/towards the light)"""
    ln = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    ndl = np.clip(nx * SUN[0] + ny * SUN[1] + nz * SUN[2], 0, 1)
    base = np.array(albedo)[None, None, :] * wetdark
    diffuse = base * (0.30 + 0.85 * ndl[..., None])
    h = SUN + np.array([0, 0, 1.0])
    h = h / np.linalg.norm(h)
    ndh = np.clip(nx * h[0] + ny * h[1] + nz * h[2], 0, 1)
    spec = 1.4 * ndh ** 160
    tilt = 1 - nz
    sky = (0.10 + 0.9 * np.clip(-ny * 0.6 - nx * 0.4 + 0.15, 0, 1) * tilt * 6.0).clip(0, 0.9)    # the sky is above: normals leaning up the panel pick it up
    sky = sky * 0.7
    rgb = diffuse + spec[..., None] + sky[..., None] * 0.35
    return rgb


def look_a(albedo, seed):
    x, y = grid()
    nx = np.zeros_like(x)
    ny = np.zeros_like(x)
    nz = np.ones_like(x)
    img = shade(albedo, nx, ny, nz)
    mult = np.ones_like(x)
    for cx, cy, r in drops(36, 3.0, 6.0, seed):
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r
        ring = np.clip(1 - np.abs(d - 0.8) / 0.25, 0, 1) * (d < 1.05)
        lower = np.clip(((x - cx) + (y - cy)) / (r * 1.4) * 0.7, 0, 1)
        shade_ = np.clip(ring * (0.5 + 0.4 * lower) + (d < 1) * (0.3 + 0.15 * lower), 0, 0.9)
        mult *= 1 - shade_
    return np.clip(img * mult[..., None], 0, 1)


def look_b(albedo, seed):
    x, y = grid()
    img = shade(albedo, np.zeros_like(x), np.zeros_like(x), np.ones_like(x))
    mult = np.ones_like(x)
    for cx, cy, r in drops(220, 0.35, 1.5, seed):
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r
        ring = np.clip(1 - np.abs(d - 0.85) / 0.3, 0, 1) * (d < 1.3)
        mult *= 1 - 0.35 * ring
    return np.clip(img * mult[..., None], 0, 1)


def look_d(albedo, seed):
    """a transparent body with a thin dark rim (the base map multiplies) and a bright glint: the palette is punched and the base map painted light there, the way the
    scratches are drawn, so the glint is white paint, lit by the scene (it goes dark at night), not a multiply"""
    x, y = grid()
    mult = np.ones_like(x)
    glint = np.zeros_like(x)
    for cx, cy, r in drops(220, 0.35, 1.5, seed):
        dx, dy = x - cx, y - cy
        d = np.sqrt(dx * dx + dy * dy) / r
        ring = np.clip(1 - np.abs(d - 0.85) / 0.3, 0, 1) * (d < 1.3)
        low = np.clip((dx + dy) / (r * 1.4), 0, 1)                     # the rim is darker low right
        mult *= 1 - (0.22 + 0.2 * low) * ring
        gd = np.sqrt((dx + 0.38 * r) ** 2 + (dy + 0.38 * r) ** 2) / (0.32 * r)
        glint = np.maximum(glint, np.clip(1.4 - gd, 0, 1))
    alb = np.array(albedo)[None, None, :] * (1 - glint[..., None]) + 0.92 * glint[..., None]
    h, w = x.shape
    img = shade_albedo(alb)
    return np.clip(img * mult[..., None], 0, 1)


def shade_albedo(alb):
    """the same clear-coat model with a per-pixel albedo on a flat panel"""
    nx = np.zeros(alb.shape[:2])
    ny = np.zeros(alb.shape[:2])
    nz = np.ones(alb.shape[:2])
    ndl = np.clip(nz * SUN[2], 0, 1)
    diffuse = alb * (0.30 + 0.85 * ndl)[..., None]
    h = SUN + np.array([0, 0, 1.0])
    h = h / np.linalg.norm(h)
    return diffuse + 0.035                                   # (the flat paint's own sun glint is left out: the same everywhere, so it does not change the comparison)


def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) ** (1 / 1.8) * 255).astype(np.uint8))        # a plain display gamma


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'waterlook.png'
    looks = [('A  now: dark discs, 3-6 texels (3-6 cm)', look_a), ('B  multiply only, real size, thin rim', look_b), ('D  thin rim + glint, transparent body, real size', look_d)]
    tile = W * S, H * S
    sheet = Image.new('RGB', (tile[0] * 3 + 40, (tile[1] + 28) * 3 + 20), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for row, (pname, albedo) in enumerate(PAINTS.items()):
        for col, (lname, fn) in enumerate(looks):
            im = to_img(fn(albedo, 11 + row))
            x0, y0 = 10 + col * (tile[0] + 10), 10 + row * (tile[1] + 28)
            sheet.paste(im, (x0, y0 + 18))
            dr.text((x0, y0), pname + ' paint: ' + lname, fill=(255, 255, 255))
    sheet.save(out)
    print('wrote', out, sheet.size)


if __name__ == '__main__':
    main()
