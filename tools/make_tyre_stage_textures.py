"""Tyre wear overlays: python tools/make_tyre_stage_textures.py  ->  tools/_out_tyre_overlays/*.png
Full-atlas DETAIL maps (detailScale 1,1) for the stock tire_01a atlas (1024 x 512, tread = the central band, sidewall lettering above and below). They touch only the tread band, so the lettering stays:
  tyre_wear_r  roughness detail: a little glossier worn tread
  tyre_wear_c  colour detail (linear data, 0.5 = no change; the engine adds (d * 2 - 1) x strength to the base colour): the worn tread greys and scuffs, less at the shoulders
  tyre_cord_c  colour detail: the belts, tan cord weave with dark rubber remnants
  tyre_cord_n  normal detail: the weave and the remnants
Everything is periodic round the tyre (the U direction, columns), so there is no seam. Procedural, no photographs.
Shipping: the game cooks a PNG to BC7 / BC5 DDS the first time it is used and then reloads the texture, which strips the maps from a material that was switched in at spawn (neon lettering on a black tyre), and a
DDS of our own in a format other than the cooker's logs an E line per file. So: copy the four PNGs into the mod's art/surfacefx/tyres, spawn a car with the tyres on, copy the cooked
<user folder>/current/temp/art/surfacefx/tyres/*.dds back into the mod, delete the PNGs (the materials name them .png, as the game's own materials name their DDS files). Parameters: SIZE, BAND (the tread band as a fraction of the height).
"""
import os
import numpy as np
from PIL import Image

W, H = 1024, 512
BAND = (0.285, 0.715)           # tire_01a atlas: tread rows
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_out_tyre_overlays')      # PNG sources; the shipped files are the game's own cooked DDS of them (see below)
os.makedirs(OUT, exist_ok=True)
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
inband = smooth(V, BAND[0] - 0.03, BAND[0] + 0.02) * (1 - smooth(V, BAND[1] - 0.02, BAND[1] + 0.03))
shoulder = 0.55 + 0.45 * (1 - (2 * t - 1) ** 2)       # the centre wears most


def save(a, name, mode=None):
    img = Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8), mode)
    img.save(os.path.join(OUT, name))


# worn: only a slight lift of the stock tread tone (linear, about +0.07 at the centre, patchy, less at the shoulders); the wear is carried by the flattened normal and the sheen map
patch = noise(16, 6, 1) * 0.5 + noise(64, 24, 2) * 0.3 + noise(256, 12, 3) * 0.2
streak = noise(8, 96, 4)
delta = (0.045 + 0.04 * patch + 0.02 * streak) * shoulder * inband
wear = 0.5 + 0.5 * delta[..., None] * np.array([1.0, 0.97, 0.92])
save(wear.astype(np.float32), 'tyre_wear_c.data.png')
# sheen: the roughness detail (0.5 = no change, lower = shinier, the engine adds (d * 2 - 1) x strength to the stock roughness): a smooth worn tread is a little glossier, most at the centre
sheen = 0.5 - 0.5 * (0.45 + 0.1 * patch) * shoulder * inband
save(sheen[..., None].repeat(3, -1).astype(np.float32), 'tyre_wear_r.data.png')

# belts: a fine diagonal weave (silver steel wire in some zones, pale tan textile in others) and TORN rubber left in long ragged streaks along the rolling direction (few cells round, many across)
wu = (U * 170 + V * 85) % 1.0
wv = (U * 170 - V * 85) % 1.0
over = (np.sin(2 * np.pi * (U * 85)) * np.sin(2 * np.pi * (V * 42)) > 0)
weave = np.where(over, 0.35 + 0.65 * np.sin(np.pi * wu) ** 2, 0.35 + 0.65 * np.sin(np.pi * wv) ** 2)
streaks = noise(5, 56, 5) * 0.55 + noise(14, 150, 6) * 0.3 + noise(40, 220, 8) * 0.15       # ragged: long in U
remnant = smooth(streaks, 0.6, 0.66) * (0.6 + 0.4 * noise(3, 9, 9))
cordmask = inband * (1 - remnant)
zone = smooth(noise(9, 30, 10), 0.45, 0.58)                                                    # 1 = textile, 0 = steel wire
steel = np.array([0.62, 0.63, 0.66])
tan = np.array([0.88, 0.74, 0.5])
tone = steel[None, None, :] * (1 - zone[..., None]) + tan[None, None, :] * zone[..., None]
cord_delta = tone * (0.6 + 0.4 * weave)[..., None] * cordmask[..., None]
cord_delta += np.array([0.012, 0.012, 0.012])[None, None, :] * (inband * remnant)[..., None]      # the torn rubber stays dark
save((0.5 + 0.5 * cord_delta).astype(np.float32), 'tyre_cord_c.data.png')

# belts normal: the thread slopes, strong, flat on the rubber remnants (OpenGL, green up)
gx = np.cos(2 * np.pi * wu) * 0.5 + np.cos(2 * np.pi * wv) * 0.5
gy = np.cos(2 * np.pi * wu) * 0.5 - np.cos(2 * np.pi * wv) * 0.5
amp = 0.9 * cordmask
nx, ny = gx * amp, gy * amp
nz = np.sqrt(np.clip(1 - nx ** 2 - ny ** 2, 0, 1))
save(np.stack([0.5 + 0.5 * nx, 0.5 + 0.5 * ny, 0.5 + 0.5 * nz], -1).astype(np.float32), 'tyre_cord_n.normal.png')
print('wrote tyre_wear_c.data.png, tyre_wear_r.data.png, tyre_cord_c.data.png, tyre_cord_n.normal.png to', os.path.abspath(OUT))
