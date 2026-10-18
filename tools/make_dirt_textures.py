"""Our own dirt textures for the paint canvas (docs/DIRT_RESEARCH.md, "How it looks"): python tools/make_dirt_textures.py [out folder]

Writes mod/art/surfacefx/dirt/*.png and atlas.json. Every picture is a MASK: white pixels, the alpha channel is how much dirt lies there (the page tints it with the dirt's colour),
except cakes.png, whose rgb is the shade of the clod (a grey the page multiplies with the mud colour) and whose alpha is its outline. Nothing here is copied from anywhere: all the
shapes are made from seeded noise, so the same script gives the same pictures.
    film.png     256x256  tileable   road film: an even soft haze, a little grain, no particles
    dust.png     256x256  tileable   dried dust: pale and matt, a fine powder with a few soft patches
    speckle.png  512x512  atlas 2x2 splash: dots of many sizes in fan-shaped streaks; each cell 256x256, the fan opens UP from the bottom-centre of the cell (rotate to the spray)
    cakes.png    512x256  atlas 4x2  mud clods 128x128: top row wet (thick, dark, rough edge, lumpy), bottom row the same four dried (lighter, cracked); a few thrown droplets around
    streaks.png  128x512  tileable in V  runs of dirt carried down by water: thin vertical runs that darken toward the bottom where they end in a drip; down is +y
At the canvas' 5 mm a texel (1024 over the paint UV) a cake of 8 to 14 texels is a 4 to 7 cm clod, a speckle cell is drawn about 60 to 100 texels (30 to 50 cm), the film tile 128 to 256 texels
(0.6 to 1.3 m), the streak tile 80 to 200 texels long (40 cm to 1 m).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'mod', 'art', 'surfacefx', 'dirt')
os.makedirs(OUT, exist_ok=True)


def fnoise(n, beta, seed, m=None):
    """periodic noise n x m (tileable), power ~ 1/f^beta, scaled to 0..1"""
    m = m or n
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((m, n)))
    fy, fx = np.meshgrid(np.fft.fftfreq(m), np.fft.fftfreq(n), indexing='ij')
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1
    f = f / r ** (beta / 2)
    f[0, 0] = 0
    a = np.real(np.fft.ifft2(f))
    a = (a - a.min()) / (a.max() - a.min())
    return a


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def save_mask(alpha, name):
    rgba = np.zeros(alpha.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(rgba).save(os.path.join(OUT, name))


def film():
    low, mid, fine = fnoise(256, 2.6, 11), fnoise(256, 1.8, 12), fnoise(256, 0.4, 13)
    a = 0.30 + 0.38 * smooth(low, 0.15, 0.85) + 0.12 * (mid - 0.5) + 0.10 * (fine - 0.5)       # a haze that never quite goes clear, never solid
    save_mask(np.clip(a, 0, 0.7), 'film.png')


def dust():
    grain = fnoise(256, 0.2, 21)
    patch = fnoise(256, 2.8, 22)
    a = smooth(grain, 0.35, 0.95) * (0.25 + 0.75 * smooth(patch, 0.2, 0.8))
    save_mask(np.clip(a * 0.85, 0, 0.8), 'dust.png')


def speckle():
    S, SS = 256, 2
    sheet = Image.new('L', (512, 512), 0)
    for v in range(4):
        rng = np.random.default_rng(300 + v)
        im = Image.new('L', (S * SS, S * SS), 0)
        dr = ImageDraw.Draw(im)
        ox, oy = S * SS / 2, (S - 6) * SS
        axes = np.sort(rng.uniform(-0.62, 0.62, 9))                   # the streaks of the fan, radians off "up"
        for _ in range(1000):
            u = rng.random()
            d = (S - 24) * SS * (0.04 + 0.96 * u ** 1.5)                               # denser near the wheel
            ax = axes[rng.integers(len(axes))]
            th = ax + rng.normal(0, 0.03 + 0.05 * u)
            x, y = ox + d * np.sin(th), oy - d * np.cos(th)
            size = float(np.exp(rng.normal(np.log(0.9 + 1.7 * (1 - u) ** 1.2), 0.5))) * SS
            size = min(size, 5 * SS)
            along = size * (1 + 0.9 * u * rng.random())                # drops further out are stretched along the throw
            a = int(255 * (0.55 + 0.45 * rng.random()) * (1 - 0.55 * u))
            c, s = np.cos(th), np.sin(th)
            n = 10
            pts = []
            for k in range(n):
                t = 2 * np.pi * k / n
                px, py = size * np.cos(t), along * np.sin(t)           # y along the throw (up the picture is -y)
                pts.append((x + px * c + py * s, y + px * s - py * c))
            dr.polygon(pts, fill=a)
        im = im.resize((S, S), Image.LANCZOS)
        sheet.paste(im, ((v % 2) * S, (v // 2) * S))
    a = np.asarray(sheet, np.float32) / 255
    save_mask(a, 'speckle.png')


def cake_cell(seed, dry):
    N, SS = 128, 3
    rng = np.random.default_rng(seed)                                  # (the same seed for the wet and the dry one: the same clod)
    P = N * SS
    yy, xx = np.mgrid[0:P, 0:P].astype(np.float32)
    cx = cy = P / 2
    dx, dy = xx - cx, yy - cy
    d, th = np.sqrt(dx * dx + dy * dy), np.arctan2(dy, dx)
    R = P * rng.uniform(0.26, 0.33)
    prof = 1.0
    for k in range(2, 7):
        prof = prof + rng.normal(0, 0.16 / k ** 0.8) * np.cos(k * th + rng.random() * 6.28)
    rough = (fnoise(P, 1.3, seed + 5) - 0.5) * P * 0.05                 # the rough edge
    edge = d + rough - R * prof
    cover = smooth(-edge, -1.2 * SS, 1.2 * SS)
    # the shade: dark at the rim, lumpy inside; dry: lighter, with a crack network (cells of a few points, the cracks are the cell borders)
    lump = fnoise(P, 2.0, seed + 6)
    inner = np.clip(-edge / (R * 0.55), 0, 1)
    shade = 0.20 + 0.30 * inner ** 0.7 + 0.14 * (lump - 0.5)
    if dry:
        pts = rng.uniform(P * 0.22, P * 0.78, (26, 2))
        dmin = np.full((P, P), 1e9, np.float32)
        d2 = np.full((P, P), 1e9, np.float32)
        for px, py in pts:
            dd = np.sqrt((xx - px) ** 2 + (yy - py) ** 2)
            d2 = np.minimum(d2, np.maximum(dd, dmin))
            dmin = np.minimum(dmin, dd)
        crack = 1 - smooth(d2 - dmin, 0.8 * SS, 2.8 * SS)               # 1 on a crack
        shade = 0.40 + 0.26 * inner ** 0.6 + 0.12 * (lump - 0.5) - 0.34 * crack * smooth(inner, 0.02, 0.35)
        shade = shade - 0.12 * (1 - inner)
    # thrown droplets around the clod
    drops = Image.new('L', (P, P), 0)
    dd_ = ImageDraw.Draw(drops)
    for _ in range(int(rng.integers(5, 11))):
        a = rng.random() * 6.283
        rr = R * rng.uniform(1.15, 1.9)
        r0 = P * rng.uniform(0.006, 0.02)
        x, y = cx + rr * np.cos(a), cy + rr * np.sin(a)
        dd_.ellipse([x - r0, y - r0, x + r0, y + r0], fill=255)
    dm = np.asarray(drops, np.float32) / 255
    cover = np.maximum(cover, dm)
    shade = np.where(cover > 0, np.where(dm > cover - 0.01, 0.3, shade), 0)
    rgba = np.zeros((P, P, 4), np.float32)
    rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = np.clip(shade, 0, 1) * cover       # premultiplied for a clean downsample
    rgba[..., 3] = cover
    small = rgba.reshape(N, SS, N, SS, 4).mean(axis=(1, 3))
    a = small[..., 3]
    rgb = np.where(a[..., None] > 1e-4, small[..., :3] / np.maximum(a[..., None], 1e-4), 0)
    return np.clip(rgb, 0, 1), a


def cakes():
    sheet = np.zeros((256, 512, 4), np.uint8)
    for row in range(2):
        for v in range(4):
            rgb, a = cake_cell(500 + v, row == 1)
            cell = np.zeros((128, 128, 4), np.uint8)
            cell[..., :3] = (rgb * 255 + 0.5).astype(np.uint8)
            cell[..., 3] = (a * 255 + 0.5).astype(np.uint8)
            sheet[row * 128:(row + 1) * 128, v * 128:(v + 1) * 128] = cell
    Image.fromarray(sheet).save(os.path.join(OUT, 'cakes.png'))


def streaks():
    W, H = 128, 512
    rng = np.random.default_rng(700)
    a = np.zeros((H, W), np.float32)
    wob = fnoise(H, 2.4, 701, 1)[0]
    for _ in range(40):
        x0 = rng.uniform(4, W - 4)
        w = rng.uniform(0.8, 2.6)
        L = int(rng.uniform(90, 400))
        y0 = int(rng.integers(0, H))
        amp = rng.uniform(0.25, 0.6)
        xs = np.arange(W, dtype=np.float32)
        for j in range(L):
            y = (y0 + j) % H
            t = j / L
            x = x0 + (wob[(y + int(x0 * 7)) % H] - 0.5) * 5 * t
            prof = amp * (0.3 + 0.7 * t ** 1.5)                          # darker toward the end
            head = 1 + 1.6 * smooth(t, 0.9, 1.0) * (1 - smooth(t, 0.985, 1.0))   # the drip at its end
            ww = w * head * (1 - 0.25 * (1 - t))
            a[y] = np.maximum(a[y], prof * np.exp(-((xs - x) ** 2) / (2 * ww * ww)) * (1.5 if t > 0.97 else 1))
    a = np.clip(a, 0, 0.8)
    save_mask(a, 'streaks.png')


def main():
    film(); dust(); speckle(); cakes(); streaks()
    atlas = {
        'film': {'file': 'film.png', 'size': [256, 256], 'tile': 'both', 'use': 'mask: tint grey-brown; draw tiled over the lower band and rear faces, alpha by the grime amount and the height fall-off'},
        'dust': {'file': 'dust.png', 'size': [256, 256], 'tile': 'both', 'use': 'mask: pale; on the PALETTE canvas (destination-out lightens) or tint very light; the base canvas can only darken'},
        'speckle': {'file': 'speckle.png', 'size': [512, 512], 'cells': [[0, 0, 256, 256], [256, 0, 256, 256], [0, 256, 256, 256], [256, 256, 256, 256]], 'origin': [128, 250], 'axis': 'up', 'use': 'mask: tint the dirt colour; origin is the wheel, the fan opens up; rotate so up points along the spray; scale 60 to 100 texels'},
        'cakes': {'file': 'cakes.png', 'size': [512, 256], 'cell': 128, 'wet': [0, 1, 2, 3], 'dry': [4, 5, 6, 7], 'use': 'rgb = shade (multiply with the mud colour), alpha = outline; index i: x = (i%4)*128, y = floor(i/4)*128; draw wet when the mud is fresh, cross-fade to the dry cell as it dries; 8 to 14 texels'},
        'streaks': {'file': 'streaks.png', 'size': [128, 512], 'tile': 'v', 'use': 'mask: tint the dirt colour; down is +y; on vertical panels, alpha by the rain-streaked share; 80 to 200 texels long'},
        'mmPerTexel': 5,
    }
    with open(os.path.join(OUT, 'atlas.json'), 'w') as f:
        json.dump(atlas, f, indent=1)
    print('wrote', os.path.abspath(OUT))


if __name__ == '__main__':
    main()
