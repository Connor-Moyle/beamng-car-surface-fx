"""Tyre wear overlays: python tools/make_tyre_stage_textures.py  ->  mod/art/surfacefx/tyres/tyre_wear_c.data.png, tyre_cord_c.data.png, tyre_cord_n.normal.png
Full-atlas DETAIL maps (detailScale 1,1) for the stock tire_01a atlas (1024 x 512, tread = the central band, sidewall lettering above and below). They touch only the tread band, so the lettering stays:
  tyre_wear_c  colour detail (linear data, 0.5 = no change; the engine adds (d * 2 - 1) x strength to the base colour): the worn tread greys and scuffs, less at the shoulders
  tyre_cord_c  colour detail: the belts, tan cord weave with dark rubber remnants
  tyre_cord_n  normal detail: the weave and the remnants
Everything is periodic round the tyre (the U direction, columns), so there is no seam. Procedural, no photographs. Parameters: SIZE, BAND (the tread band as a fraction of the height).
"""
import os
import numpy as np
from PIL import Image

W, H = 1024, 512
BAND = (0.273, 0.723)           # tire_01a atlas: tread rows
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'mod', 'art', 'surfacefx', 'tyres')
rng = np.random.default_rng(7)


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def noise(cells_u, cells_v, seed):
    """periodic in both directions: random grid values, cosine-interpolated"""
    r = np.random.default_rng(seed)
    g = r.random((cells_v, cells_u)).astype(np.float32)
    u = np.arange(W) / W * cells_u
    v = np.arange(H) / H * cells_v
    u0 = np.floor(u).astype(int)
    v0 = np.floor(v).astype(int)
    fu = smooth(u - u0, 0, 1)[None, :]
    fv = smooth(v - v0, 0, 1)[:, None]
    a = g[v0 % cells_v][:, u0 % cells_u]
    b = g[v0 % cells_v][:, (u0 + 1) % cells_u]
    c = g[(v0 + 1) % cells_v][:, u0 % cells_u]
    d = g[(v0 + 1) % cells_v][:, (u0 + 1) % cells_u]
    return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv


V, U = np.meshgrid((np.arange(H) + 0.5) / H, (np.arange(W) + 0.5) / W, indexing='ij')
t = np.clip((V - BAND[0]) / (BAND[1] - BAND[0]), 0, 1)
inband = smooth(V, BAND[0] - 0.012, BAND[0] + 0.012) * (1 - smooth(V, BAND[1] - 0.012, BAND[1] + 0.012))
shoulder = 0.55 + 0.45 * (1 - (2 * t - 1) ** 2)       # the centre wears most


def save(a, name, mode=None):
    img = Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8), mode)
    img.save(os.path.join(OUT, name))


# worn: the colour added on top of the stock tread (linear): about +0.11 at the centre, patchy, with scuff streaks round the tyre
patch = noise(16, 6, 1) * 0.5 + noise(64, 24, 2) * 0.3 + noise(256, 12, 3) * 0.2
streak = noise(8, 96, 4)
delta = (0.075 + 0.07 * patch + 0.03 * streak) * shoulder * inband
wear = 0.5 + 0.5 * delta[..., None] * np.array([1.0, 0.96, 0.88])      # a little warm grey
save(wear.astype(np.float32), 'tyre_wear_c.data.png')

# cord: weave of two thread sets at +-45 degrees; remnants of rubber where a noise field is high (they keep the stock dark tread)
wu = (U * 96 + V * 48) % 1.0
wv = (U * 96 - V * 48) % 1.0
thread = 0.5 + 0.5 * np.maximum(np.sin(2 * np.pi * wu), np.sin(2 * np.pi * wv))
over = (np.sin(2 * np.pi * (U * 48)) * np.sin(2 * np.pi * (V * 24)) > 0)        # which set lies on top
weave = np.where(over, 0.55 + 0.45 * np.sin(2 * np.pi * wu) ** 2, 0.55 + 0.45 * np.sin(2 * np.pi * wv) ** 2)
remnant = smooth(noise(14, 5, 5) * 0.6 + noise(56, 20, 6) * 0.4, 0.55, 0.68)     # 1 = rubber left
cordmask = inband * (1 - remnant)
cord_delta = np.array([0.30, 0.22, 0.12])[None, None, :] * (0.5 + 0.5 * weave)[..., None] * cordmask[..., None]
cord_delta += np.array([0.03, 0.03, 0.03])[None, None, :] * (inband * remnant)[..., None]      # remnants: only a little lighter than the tread
save((0.5 + 0.5 * cord_delta).astype(np.float32), 'tyre_cord_c.data.png')

# cord normal: slopes of the two threads (OpenGL, green up), flat outside the band and on the remnants
gx = np.cos(2 * np.pi * wu) * 0.5 + np.cos(2 * np.pi * wv) * 0.5
gy = np.cos(2 * np.pi * wu) * 0.5 - np.cos(2 * np.pi * wv) * 0.5
amp = 0.45 * cordmask
nx, ny = gx * amp, gy * amp
nz = np.sqrt(np.clip(1 - nx ** 2 - ny ** 2, 0, 1))
save(np.stack([0.5 + 0.5 * nx, 0.5 + 0.5 * ny, 0.5 + 0.5 * nz], -1).astype(np.float32), 'tyre_cord_n.normal.png')
print('wrote tyre_wear_c.data.png, tyre_cord_c.data.png, tyre_cord_n.normal.png to', os.path.abspath(OUT))
