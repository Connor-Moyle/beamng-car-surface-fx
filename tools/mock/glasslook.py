"""Mock-up of the window drops (glass.js) at real size, old sprite against the new bead, on a dark and a light tinted glass: python tools/mock/glasslook.py [out.png]

A canvas of 200 x 120 px (about 0.45 m x 0.27 m of glass at 2.3 mm a pixel), drops of 1 to 4 px radius (2 to 8 mm across or so), drawn at 8x and averaged down, then shown at 4x.
Rows: dark tint, light tint (the colour map: the drops are drawn over the tinted glass image) and the emissive map (light that is ADDED to a dark clear pane).
Columns: the old drops, the new bead (a clear body, a thin dark edge, a glint). The formulas are those of glass.js, evaluated per pixel; a drop under 2.2 px is the ring and the one-pixel
glint, as the page draws it.
"""
import sys

import numpy as np
from PIL import Image, ImageDraw

W, H, SS, ZOOM = 200, 120, 8, 4
rng = np.random.default_rng(3)
DROPS = [(rng.random() * W, rng.random() * H, 1.0 + 3.0 * rng.random() ** 2) for _ in range(150)]


def sprite_old(u, v, emissive):
    d = np.sqrt(u * u + v * v)
    fade = np.clip((1 - d) * 8, 0, 1)
    ring = np.clip(1 - np.abs(d - 0.86) / 0.14, 0, 1)
    dirn = (u + v) * 0.7071
    s = ring * np.where(dirn > 0, -0.32 * dirn, 0.6 * -dirn)
    gx, gy = u + 0.4, v + 0.45
    s = s + 0.95 * np.exp(-(gx * gx + gy * gy) / 0.012)
    s = s - 0.06 * np.maximum(0, dirn) * (1 - ring)
    if emissive:
        s = np.maximum(0, s - 0.12 + 0.06 * (1 - np.minimum(1, d * 1.5)))
    colour = np.where(s >= 0, 1.0, 0.0)
    alpha = np.minimum(1, np.abs(s)) * fade
    return colour, np.where(d < 1, alpha, 0)


def sprite_new(u, v, emissive):
    d = np.sqrt(u * u + v * v)
    ring = np.clip(1 - np.abs(d - 0.84) / 0.16, 0, 1)
    low = np.clip((u + v) * 0.7, 0, 1)
    gx, gy = u + 0.38, v + 0.42
    glint = np.exp(-(gx * gx + gy * gy) / 0.014)
    if emissive:
        lit = ring * np.clip(-(u + v) * 0.7, 0, 1) * 0.45
        a = np.minimum(1, lit + glint * 0.95)
        return np.ones_like(a), np.where(d < 1.1, a, 0)
    spot = np.where(d < 0.8, 0.14 * np.exp(-((u - 0.25) ** 2 + (v - 0.3) ** 2) / 0.12), 0)
    dark = ring * (0.32 + 0.40 * low)
    lightA = np.minimum(1, glint * 0.95 + spot)
    a = lightA + dark * (1 - lightA)
    lum = np.where(a > 0, lightA / np.maximum(a, 1e-9), 0)
    return lum, np.where(d < 1.1, a, 0)


def render(bg, emissive, new):
    """returns the canvas at 1x as float rgb 0..1"""
    img = np.empty((H * SS, W * SS, 3), np.float32)
    img[:] = np.array(bg, np.float32)[None, None, :] / 255
    glints = []
    for cx, cy, R in DROPS:
        px, py = cx * SS, cy * SS
        if new and R < 2.2:
            rr = max(0.6, R) * SS
            if not emissive:
                x0, x1, y0, y1 = int(px - rr - 6), int(px + rr + 6), int(py - rr - 6), int(py + rr + 6)
                ys, xs = np.mgrid[max(0, y0):min(H * SS, y1), max(0, x0):min(W * SS, x1)]
                dd = np.sqrt((xs - px) ** 2 + (ys - py) ** 2)
                ring = np.clip(1 - np.abs(dd - rr) / (0.35 * SS), 0, 1) * 0.38
                img[ys, xs] = img[ys, xs] * (1 - ring[..., None])
            glints.append((px - (0.35 * max(0.6, R) + 0.5) * SS, py - (0.4 * max(0.6, R) + 0.5) * SS))
            continue
        rs = R * SS
        x0, x1, y0, y1 = int(px - rs * 1.2 - 2), int(px + rs * 1.2 + 2), int(py - rs * 1.2 - 2), int(py + rs * 1.2 + 2)
        ys, xs = np.mgrid[max(0, y0):min(H * SS, y1), max(0, x0):min(W * SS, x1)]
        u, v = (xs - px) / rs, (ys - py) / rs
        col, a = (sprite_new if new else sprite_old)(u, v, emissive)
        a = a[..., None]
        sub = img[ys, xs]
        if emissive:
            img[ys, xs] = np.clip(sub + a * col[..., None], 0, 1)             # added light
        else:
            img[ys, xs] = sub * (1 - a) + a * col[..., None]
    for gx, gy in glints:                                                        # the one-pixel glints
        x0, y0 = int(round(gx)), int(round(gy))
        if 0 <= x0 and x0 + SS <= W * SS and 0 <= y0 and y0 + SS <= H * SS:
            sub = img[y0:y0 + SS, x0:x0 + SS]
            if emissive:
                img[y0:y0 + SS, x0:x0 + SS] = np.clip(sub + 0.8, 0, 1)
            else:
                img[y0:y0 + SS, x0:x0 + SS] = sub * 0.15 + 0.85
    small = img.reshape(H, SS, W, SS, 3).mean(axis=(1, 3))
    return small


def show(a, label, dr_y):
    im = Image.fromarray((np.clip(a, 0, 1) ** (1 / 2.0) * 255).astype(np.uint8)).resize((W * ZOOM, H * ZOOM), Image.NEAREST)
    return im


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'glasslook.png'
    rows = [('dark tint, colour map', (36, 48, 54), False), ('light tint, colour map', (188, 204, 212), False), ('emissive map (added to a dark clear pane)', (0, 0, 0), True)]
    tw, th = W * ZOOM, H * ZOOM
    sheet = Image.new('RGB', (tw * 2 + 30, (th + 24) * 3 + 10), (22, 22, 22))
    dr = ImageDraw.Draw(sheet)
    for r, (name, bg, em) in enumerate(rows):
        for c, (label, new) in enumerate((('old', False), ('new bead', True))):
            im = show(render(bg, em, new), label, 0)
            x0, y0 = 10 + c * (tw + 10), 6 + r * (th + 24)
            sheet.paste(im, (x0, y0 + 16))
            dr.text((x0, y0), name + ': ' + label, fill=(255, 255, 255))
    sheet.save(out)
    print('wrote', out, sheet.size)


if __name__ == '__main__':
    main()
