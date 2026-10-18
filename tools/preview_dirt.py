"""Preview of the dirt textures: python tools/preview_dirt.py [out.png]
Top: each picture as it is (mask over a grey, cakes over a grey, 2x). Bottom: a side panel of red paint, 1.0 m x 0.55 m at the canvas' 5 mm a texel (200 x 110 texels, shown 4x), dirtied the way the
canvas does it: the base canvas MULTIPLIES the paint (dirt colour times paint), dust is lifted with the palette canvas (towards pale). Layers: road film (low, fading up), splash fan behind the
wheel arch, mud cakes on the sill and the arch lip, rain streaks, a coat of dust.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HERE, '..', 'mod', 'art', 'surfacefx', 'dirt')


def load(name):
    return np.asarray(Image.open(os.path.join(D, name)).convert('RGBA'), np.float32) / 255


def tile(a, w, h, ox=0, oy=0):
    return np.tile(a, (h // a.shape[0] + 2, w // a.shape[1] + 2) + (1,) * (a.ndim - 2))[oy:oy + h, ox:ox + w]


def rot_scale(img, angle_deg, scale):
    im = Image.fromarray((img * 255).astype(np.uint8), 'RGBA')
    im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS).rotate(angle_deg, expand=True, resample=Image.BICUBIC)
    return np.asarray(im, np.float32) / 255


def put(canvas, sprite, x, y):
    """add a sprite's alpha into a coverage canvas (max)"""
    h, w = sprite.shape[:2]
    x0, y0 = int(x - w / 2), int(y - h / 2)
    cx0, cy0, cx1, cy1 = max(0, x0), max(0, y0), min(canvas.shape[1], x0 + w), min(canvas.shape[0], y0 + h)
    if cx1 <= cx0 or cy1 <= cy0:
        return
    sub = sprite[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
    canvas[cy0:cy1, cx0:cx1] = 1 - (1 - canvas[cy0:cy1, cx0:cx1]) * (1 - sub)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'dirt_preview.png'
    film, dust, speck, cakes, streaks = (load(n) for n in ('film.png', 'dust.png', 'speckle.png', 'cakes.png', 'streaks.png'))
    W, H = 200, 110
    rng = np.random.default_rng(5)
    paint = np.zeros((H, W, 3), np.float32)
    paint[:] = np.array([0.62, 0.06, 0.07])
    yy = np.linspace(0, 1, H)[:, None]                                  # 0 top, 1 bottom (the sill)
    xx = np.linspace(0, 1, W)[None, :]
    wheel = (0.78 * W, 0.98 * H)                                        # the rear wheel arch at the right
    arch = np.sqrt(((np.arange(W)[None, :] - wheel[0]) / (0.2 * W)) ** 2 + ((np.arange(H)[:, None] - wheel[1]) / (0.52 * H)) ** 2) < 1
    # layers: coverage 0..1 each
    cov_film = tile(film[..., 3], W, H, 17, 9) * (1 - yy) ** 0 * np.clip(1.15 - yy * 1.0, 0, 1) ** 0 * np.clip((yy - 0.35) / 0.6, 0, 1) * 0.9
    cov_dust = tile(dust[..., 3], W, H, 40, 3) * np.clip(0.8 - 0.8 * (1 - yy) ** 0.6, 0, 1) * 0.9
    cov_spk = np.zeros((H, W), np.float32)
    for v in range(4):
        cell = speck[(v // 2) * 256:(v // 2) * 256 + 256, (v % 2) * 256:(v % 2) * 256 + 256]
        for k in range(1):
            ang = rng.uniform(-10, 55)                                  # fan up and back (to the left) from the wheel
            spr = rot_scale(cell, ang, 0.30)
            put(cov_spk, spr[..., 3], wheel[0] - 14 - v * 14, wheel[1] - 20 - 3 * v)
    cov_spk = cov_spk * 0.8
    cov_cake = np.zeros((H, W), np.float32)
    cake_rgb = np.ones((H, W), np.float32)
    for i in range(30):
        row = 1 if rng.random() < 0.35 else 0
        v = rng.integers(0, 4)
        cell = cakes[row * 128:(row + 1) * 128, v * 128:(v + 1) * 128]
        spr = rot_scale(cell, rng.uniform(0, 360), rng.uniform(0.07, 0.13))
        x = rng.choice([rng.uniform(0.08, 0.6) * W, wheel[0] + rng.normal(0, 0.12 * W)])
        y = H * rng.uniform(0.9, 0.99) if x < 0.66 * W or rng.random() < 0.5 else H * rng.uniform(0.6, 0.85)
        h, w = spr.shape[:2]
        x0, y0 = int(x - w / 2), int(y - h / 2)
        cx0, cy0, cx1, cy1 = max(0, x0), max(0, y0), min(W, x0 + w), min(H, y0 + h)
        if cx1 > cx0 and cy1 > cy0:
            sub = spr[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
            m = sub[..., 3] > cov_cake[cy0:cy1, cx0:cx1]
            cake_rgb[cy0:cy1, cx0:cx1] = np.where(m, sub[..., 0], cake_rgb[cy0:cy1, cx0:cx1])
            cov_cake[cy0:cy1, cx0:cx1] = np.maximum(cov_cake[cy0:cy1, cx0:cx1], sub[..., 3])
    cov_str = tile(streaks[..., 3], W, H, 0, 130) * np.clip((yy - 0.15) / 0.5, 0, 1) * 1.0
    cov_str = cov_str * (1 - arch)
    # the canvas: dirt colour multiplies the paint; dust lifts it (palette punch)
    img = paint.copy()
    def multiply(img, cov, col, amount=1.0):
        c = np.array(col, np.float32)
        return img * (1 - cov[..., None] * amount * (1 - c))
    img = multiply(img, cov_film, (0.55, 0.50, 0.44), 0.85)
    img = multiply(img, cov_str, (0.40, 0.33, 0.27), 0.9)
    img = multiply(img, cov_spk, (0.33, 0.25, 0.17), 0.95)
    mudc = np.array([0.45, 0.33, 0.22], np.float32)
    img = img * (1 - cov_cake[..., None]) + cov_cake[..., None] * (mudc[None, None, :] * (cake_rgb[..., None] * 1.8))
    img = img + (np.array([0.86, 0.80, 0.68]) - img) * (cov_dust[..., None] * 0.55)
    img = np.clip(img, 0, 1)
    z = 4
    panel = Image.fromarray((img ** (1 / 1.0) * 255).astype(np.uint8)).resize((W * z, H * z), Image.BICUBIC)
    clean = Image.fromarray((paint * 255).astype(np.uint8)).resize((W * z, H * z), Image.BICUBIC)
    # top row: the textures
    bg = (120, 120, 124)
    def show(a, size, name, rgbmode=False):
        base = np.zeros(a.shape[:2] + (3,), np.float32) + np.array(bg, np.float32) / 255
        col = a[..., :3] if rgbmode else np.array([0.2, 0.14, 0.1])[None, None, :]
        r = base * (1 - a[..., 3:4]) + col * a[..., 3:4]
        im = Image.fromarray((np.clip(r, 0, 1) * 255).astype(np.uint8))
        return im.resize(size, Image.LANCZOS), name
    items = [show(film, (256, 256), 'film 256 (tileable)'), show(dust, (256, 256), 'dust 256 (tileable)'), show(speck, (512, 512), 'speckle 2x2 fans'), show(cakes, (512, 256), 'cakes: wet / dry, 4 each', True), show(streaks, (128, 512), 'streaks (tileable in V)')]
    sheet = Image.new('RGB', (1700, 560 + H * z + 60), (24, 24, 26))
    dr = ImageDraw.Draw(sheet)
    x = 10
    for im, name in items:
        sheet.paste(im, (x, 24))
        dr.text((x, 6), name, fill=(255, 255, 255))
        x += im.width + 14
    y0 = 560
    sheet.paste(clean, (10, y0 + 22)); dr.text((10, y0 + 6), 'clean panel, 1.0 m x 0.55 m at 5 mm a texel', fill=(255, 255, 255))
    sheet.paste(panel, (W * z + 30, y0 + 22)); dr.text((W * z + 30, y0 + 6), 'all five layers (film, rain streaks, splash fan, mud cakes, dust)', fill=(255, 255, 255))
    sheet.save(out)
    print('wrote', out, sheet.size)


if __name__ == '__main__':
    main()
