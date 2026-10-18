"""Makes the PBR texture sets of the ground marks (our own, procedural, no third-party assets) and their material file:

    python tools/make_mark_textures.py [--out mod/art/surfacefx/marks] [--flip-green]

For each mark type: base colour (RGB), opacity (grey), normal (RGB), roughness (grey), and where it matters ambient occlusion (grey), named as the game's decal road
materials are (t_<type>_b.color.png, _o.data.png, _nm.normal.png, _r.data.png, _ao.data.png). Strips are tileable ALONG the road (v, the long side of the image) and fade out
at the sides; U runs across the road. Fluid stains are single blobs. Every type gets a dry and a wet material (csfx_<type>_dry, csfx_<type>_wet) in main.materials.json
in the game's material format (version 1.5, translucent, translucentZWrite, RoadAndPath); the wet one is darker with a lower roughnessFactor (fluids: their own glossy
roughness map). The normal maps are in the DirectX convention (green down) unless --flip-green; the swatch map (carSurfaceFx/markSwatches.lua) shows if a bump reads inverted.
"""
import argparse
import json
import os
import uuid

import numpy as np
from PIL import Image

STRIP_W, STRIP_H = 256, 512       # across the road, along it
THIN_W = 128
BLOB = 256


# ---- noise ---------------------------------------------------------------------------------------------------------------------------------------------

def fnoise(h, w, beta, seed, ay=1.0, ax=1.0):
    """Periodic filtered noise in -1..1. beta: the roll-off (1 grainy .. 3 smooth); ay, ax: scale of the frequencies along v and u (a LARGE ay makes the noise smooth along v: long streaks; a large ax smooth across u)."""
    rng = np.random.default_rng(seed)
    f = np.fft.rfft2(rng.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None] * ay
    fx = np.fft.rfftfreq(w)[None, :] * ax
    r = np.sqrt(fx ** 2 + fy ** 2)
    r[0, 0] = 1.0
    f = f / (r ** beta)
    f[0, 0] = 0
    out = np.fft.irfft2(f, s=(h, w))
    return out / max(np.abs(out).max(), 1e-9)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


def grid(h, w):
    u = np.linspace(-1, 1, w)[None, :] * np.ones((h, 1))
    v = np.arange(h)[:, None] * np.ones((1, w)) / h
    return u, v


def normal_from_height(hgt, strength, flip_green):
    """Tangent-space normal from a height map in units of 'the image width'; wraps along v (rows), edges clamp across u."""
    h, w = hgt.shape
    dv = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * 0.5 * (h / 2.0)
    pad = np.pad(hgt, ((0, 0), (1, 1)), mode='edge')
    du = (pad[:, 2:] - pad[:, :-2]) * 0.5 * (w / 2.0)
    nx, ny = -du * strength / w * 4.0, -dv * strength / w * 4.0
    nz = np.ones_like(nx)
    ln = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    if flip_green:
        ny = -ny
    rgb = np.stack([nx * 0.5 + 0.5, 0.5 - ny * 0.5, nz * 0.5 + 0.5], -1)       # (DirectX: green points down)
    return rgb


def u8(a):
    return np.clip(np.round(a * 255), 0, 255).astype(np.uint8)


def band(u, half, soft, edge_noise, ragged):
    """1 inside |u| < half, soft edge, edge pushed in and out by noise."""
    d = np.abs(u) + edge_noise * ragged
    return 1.0 - smooth(half - soft, half + soft, d)


# ---- the strips ----------------------------------------------------------------------------------------------------------------------------------------

def tread(u, v, pitch, angle, sharp):
    """a chevron tread: blocks every 1/pitch along v, slanted by angle across u; 0..1"""
    s = np.sin(2 * np.pi * (v * pitch + np.abs(u) * angle))
    return smooth(-sharp, sharp, s)


def make_skid(seed, flip):
    H, W = STRIP_H, THIN_W
    u, v = grid(H, W)
    ragged = fnoise(H, W, 1.6, seed, ay=2.0)
    streak = fnoise(H, W, 1.2, seed + 1, ay=8.0, ax=1.0) * 0.5 + 0.5
    grain = fnoise(H, W, 0.8, seed + 2)
    a = band(u, 0.62, 0.22, ragged, 0.18) * (0.55 + 0.45 * streak) * (0.8 + 0.2 * (1 - np.abs(u)))
    col = np.stack([0.035 + 0.01 * grain, 0.035 + 0.01 * grain, 0.04 + 0.01 * grain], -1)
    hgt = 0.04 * streak + 0.015 * grain
    rough = 0.55 - 0.1 * (1 - np.abs(u)) + 0.05 * grain
    return dict(color=col, opacity=a * 0.95, normal=normal_from_height(hgt, 1.0, flip), rough=rough, size=(W, H))


SURF = {   # surface colour of the ground the track is pressed into (linear-ish), the tread depth, the grain, the roughness dry
    'dirt':   dict(col=(0.30, 0.22, 0.15), depth=0.55, tread=1.0, stones=0.0, rough=0.88),
    'gravel': dict(col=(0.34, 0.31, 0.27), depth=0.45, tread=0.6, stones=1.0, rough=0.9),
    'sand':   dict(col=(0.55, 0.45, 0.30), depth=0.35, tread=0.5, stones=0.0, rough=0.95),
    'mud':    dict(col=(0.17, 0.12, 0.08), depth=0.8, tread=0.8, stones=0.0, rough=0.5),
    'snow':   dict(col=(0.78, 0.82, 0.88), depth=0.5, tread=0.7, stones=0.0, rough=0.6),
}


def make_track(name, seed, flip):
    s = SURF[name]
    H, W = STRIP_H, STRIP_W
    u, v = grid(H, W)
    ragged = fnoise(H, W, 1.5, seed, ay=2.0)
    edge = band(u, 0.55, 0.3, ragged, 0.15)
    grain = fnoise(H, W, 1.0, seed + 1)
    big = fnoise(H, W, 2.2, seed + 2, ay=3.0)
    t = tread(u, v, 14, 0.9, 0.35)
    stones = (fnoise(H, W, 0.5, seed + 3) > 0.45).astype(float) * s['stones']
    stones = np.clip(stones + 0.0, 0, 1)
    pressed = edge * (0.6 + 0.4 * (1 - np.abs(u) / 0.8).clip(0, 1))
    hgt = -pressed * s['depth'] * (0.8 + 0.2 * big) + pressed * t * 0.18 * s['tread'] + stones * pressed * 0.12 + 0.02 * grain
    dark = 0.55 + 0.25 * (1 - pressed) + 0.1 * big
    base = np.array(s['col'])
    col = base[None, None, :] * (dark[..., None] * (1 + 0.25 * grain[..., None]) * (1 - 0.18 * (t * pressed)[..., None]))
    if s['stones']:
        col = col * (1 - 0.3 * stones[..., None]) + 0.05 * stones[..., None]
    a = edge * (0.8 + 0.15 * grain) * smooth(0.0, 0.25, edge)
    rough = s['rough'] - (0.25 if name == 'mud' else 0.1 if name == 'snow' else 0.0) * pressed + 0.04 * grain
    ao = 1.0 - 0.45 * pressed * (1 - t * 0.5)
    return dict(color=np.clip(col, 0, 1), opacity=a, normal=normal_from_height(hgt, 2.2, flip), rough=rough, ao=ao, size=(W, H))


def make_rut(name, seed, flip):
    s = SURF[name]
    H, W = STRIP_H, STRIP_W
    u, v = grid(H, W)
    low = fnoise(H, W, 2.6, seed, ay=3.0, ax=3.0)
    grain = fnoise(H, W, 1.0, seed + 1)
    ragged = fnoise(H, W, 1.8, seed + 4, ay=2.0)
    shift = 0.04 * low
    uu = u + shift
    groove = np.exp(-(uu / 0.34) ** 2)
    lips = np.exp(-((np.abs(uu) - 0.72) / 0.17) ** 2)
    depth = s['depth'] * 1.7 * (0.85 + 0.15 * low)
    hgt = -groove * depth + lips * 0.45 * s['depth'] + 0.03 * grain
    if s['stones']:
        hgt += (fnoise(H, W, 0.5, seed + 3) > 0.5) * 0.06
    edge = band(u, 0.8, 0.12, ragged, 0.07)
    moist = groove * (0.45 if name in ('mud', 'dirt') else 0.25)
    base = np.array(s['col'])
    col = base[None, None, :] * ((0.6 + 0.3 * lips - 0.28 * groove + 0.1 * grain)[..., None] * (1 - moist[..., None] * 0.35))
    a = edge * (0.55 + 0.35 * groove + 0.25 * lips).clip(0, 1) * smooth(0.0, 0.2, edge)
    rough = s['rough'] - groove * (0.3 if name == 'mud' else 0.25 if name in ('dirt', 'snow') else 0.05) + 0.04 * grain
    ao = 1.0 - 0.6 * groove + 0.1 * lips
    return dict(color=np.clip(col, 0, 1), opacity=a, normal=normal_from_height(hgt, 3.5, flip), rough=rough, ao=ao, size=(W, H))


def make_gouge(name, seed, flip):
    H, W = STRIP_H, THIN_W
    u, v = grid(H, W)
    ragged = fnoise(H, W, 1.4, seed, ay=2.0)
    chips = fnoise(H, W, 0.9, seed + 1)
    streak = fnoise(H, W, 1.2, seed + 2, ay=8.0, ax=1.0) * 0.5 + 0.5
    core = band(u, 0.28, 0.1, ragged, 0.18)
    wide = band(u, 0.6, 0.25, ragged, 0.2)
    if name == 'asphalt':
        base, edge_col, rough0 = np.array([0.50, 0.50, 0.49]), np.array([0.03, 0.03, 0.03]), 0.8
    else:
        base, edge_col, rough0 = np.array([0.42, 0.31, 0.21]), np.array([0.2, 0.14, 0.09]), 0.9
    hgt = -core * 0.9 * (0.7 + 0.3 * streak) + (wide - core).clip(0, 1) * 0.3 * (chips * 0.5 + 0.5) + 0.05 * chips
    a = np.maximum(core * 0.95, wide * 0.55 * (0.6 + 0.4 * (chips * 0.5 + 0.5)))
    mix = core[..., None]
    col = edge_col[None, None, :] * (1 - mix) + base[None, None, :] * (0.85 + 0.2 * streak[..., None]) * mix
    rough = rough0 - 0.15 * core + 0.05 * chips
    ao = 1.0 - 0.5 * core
    return dict(color=np.clip(col, 0, 1), opacity=a, normal=normal_from_height(hgt, 3.0, flip), rough=rough, ao=ao, size=(W, H))


def make_wall(name, seed, flip):
    H, W = STRIP_H, THIN_W
    u, v = grid(H, W)
    ragged = fnoise(H, W, 1.5, seed, ay=2.0)
    streak = fnoise(H, W, 1.0, seed + 1, ay=8.0, ax=1.0)
    fine = fnoise(H, W, 1.4, seed + 2, ay=14.0, ax=0.35)
    lines = smooth(0.35, 0.6, fine)                       # thin scratch lines along the strip
    body = band(u, 0.7, 0.25, ragged, 0.2) * (0.5 + 0.5 * (streak * 0.5 + 0.5))
    if name == 'concrete':
        smear = np.array([0.74, 0.73, 0.69])
        col = smear[None, None, :] * (0.85 + 0.15 * streak[..., None]) * (1 - 0.35 * lines[..., None]) + 0.0
        a = np.clip(body * 0.7 + lines * 0.6, 0, 1) * band(u, 0.85, 0.1, ragged, 0.1)
        rough = 0.9 - 0.1 * lines
        hgt = -lines * 0.25 + 0.05 * streak
    else:
        dark = np.array([0.07, 0.07, 0.075])
        bright = np.array([0.78, 0.78, 0.8])
        col = dark[None, None, :] * (1 - lines[..., None]) + bright[None, None, :] * lines[..., None]
        a = np.clip(body * 0.75 + lines * 0.85, 0, 1) * band(u, 0.85, 0.1, ragged, 0.1)
        rough = 0.55 - 0.3 * lines + 0.05 * streak
        hgt = -lines * 0.4 + 0.04 * streak
    return dict(color=np.clip(col, 0, 1), opacity=a, normal=normal_from_height(hgt, 2.0, flip), rough=rough, size=(W, H))


# ---- the stains (blobs) --------------------------------------------------------------------------------------------------------------------------------

def blob(seed, wob=0.2):
    H = W = BLOB
    y, x = np.mgrid[0:H, 0:W]
    x = (x / (W - 1)) * 2 - 1
    y = (y / (H - 1)) * 2 - 1
    r = np.sqrt(x ** 2 + y ** 2)
    n = fnoise(H, W, 2.2, seed)
    n2 = fnoise(H, W, 1.2, seed + 1)
    rr = r + wob * n
    a = 1 - smooth(0.6, 0.86, rr)
    return x, y, r, rr, a, n, n2


def make_fluid(name, seed, flip):
    x, y, r, rr, a, n, n2 = blob(seed)
    rim = np.exp(-((rr - 0.8) / 0.07) ** 2)
    thick = a * (0.75 + 0.25 * n2)
    hgt = 0.08 * a + 0.1 * rim
    if name == 'oil':
        col = np.stack([0.03 + 0 * r, 0.025 + 0 * r, 0.02 + 0 * r], -1)
        film = rim[..., None] * np.array([0.12, 0.08, 0.16])[None, None, :]
        col = col + film
        op = a * (0.82 + 0.15 * n2) * smooth(0.0, 0.3, a)
        rw, rd = 0.07, 0.5
    elif name == 'coolant':
        col = np.stack([0.14 + 0.04 * n2, 0.55 + 0.06 * n2, 0.20 + 0.03 * n2], -1)
        op = a * (0.55 + 0.1 * n2) * smooth(0.0, 0.3, a)
        rw, rd = 0.05, 0.65
        col = col + (rim[..., None] * 0.15)
    else:                                                                  # fuel: a thin film with a faint rainbow
        hue = (rr * 2.2 + 0.3 * n2) % 1.0
        col = np.stack([0.45 + 0.25 * np.sin(2 * np.pi * hue), 0.45 + 0.25 * np.sin(2 * np.pi * (hue + 0.33)), 0.5 + 0.25 * np.sin(2 * np.pi * (hue + 0.66))], -1)
        op = a * (0.32 + 0.1 * n2) * smooth(0.0, 0.3, a)
        rw, rd = 0.06, 0.8
    rough_wet = rw + 0.02 * n2 + 0.03 * (1 - thick)
    rough_dry = rd + 0.05 * n2
    return dict(color=np.clip(col, 0, 1), opacity=op, normal=normal_from_height(hgt, 1.0, flip), rough=rough_wet, rough_dry=rough_dry, size=(BLOB, BLOB))


# ---- a test strip: raised domes and pits, to see which way the normal map is read -------------------------------------------------------------------------

def make_bump(seed, flip):
    H, W = STRIP_H, STRIP_W
    u, v = grid(H, W)
    hgt = np.zeros((H, W))
    yy, xx = np.mgrid[0:H, 0:W]
    for i in range(4):                                           # domes up the strip: the left half raised, the right half pits (pits in the same places)
        cy = (i + 0.5) * H / 4
        for cx, sign in ((W * 0.28, 1.0), (W * 0.72, -1.0)):
            r2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / (W * 0.19) ** 2
            hgt += sign * np.exp(-r2 * 2.0)
    col = np.full((H, W, 3), 0.5)
    col[:, : W // 2] = (0.55, 0.55, 0.55)
    col[:, W // 2:] = (0.45, 0.45, 0.45)
    return dict(color=col, opacity=np.ones((H, W)), normal=normal_from_height(hgt * 0.5, 4.0, flip), rough=np.full((H, W), 0.6), size=(W, H))


# ---- the list ------------------------------------------------------------------------------------------------------------------------------------------

TYPES = {}   # name -> (maker, textureLength m, width m, note)
TYPES['skid_asphalt'] = (lambda f: make_skid(11, f), 4.0, 0.35, 'rubber skid on tarmac, one tyre')
for i, n in enumerate(['dirt', 'gravel', 'sand', 'mud', 'snow']):
    TYPES['track_' + n] = ((lambda n, i: lambda f: make_track(n, 20 + i, f))(n, i), 3.0, 0.5, 'tyre track with tread in ' + n)
    TYPES['rut_' + n] = ((lambda n, i: lambda f: make_rut(n, 40 + i, f))(n, i), 4.0, 0.9, 'deep wheel rut with raised lips in ' + n)
TYPES['gouge_asphalt'] = (lambda f: make_gouge('asphalt', 60, f), 3.0, 0.45, 'ground gouge scar on tarmac')
TYPES['gouge_dirt'] = (lambda f: make_gouge('dirt', 61, f), 3.0, 0.45, 'ground gouge in soil')
TYPES['wall_concrete'] = (lambda f: make_wall('concrete', 70, f), 3.0, 0.5, 'scrape streak from a concrete wall')
TYPES['wall_metal'] = (lambda f: make_wall('metal', 71, f), 3.0, 0.5, 'scrape streak from a metal barrier')
TYPES['oil'] = (lambda f: make_fluid('oil', 80, f), 1.0, 1.0, 'oil stain')
TYPES['coolant'] = (lambda f: make_fluid('coolant', 81, f), 1.0, 1.0, 'coolant stain')
TYPES['fuel'] = (lambda f: make_fluid('fuel', 82, f), 1.0, 1.0, 'fuel stain with a faint sheen')
TYPES['test_bump'] = (lambda f: make_bump(90, f), 4.0, 1.0, 'TEST: domes on the left, pits on the right, to see which way the normal map is read')
FLUIDS = ('oil', 'coolant', 'fuel')


def save(path, arr, mode):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im = Image.fromarray(u8(arr) if arr.dtype != np.uint8 else arr)
    im.save(path, optimize=True)


def material(name, kind, folder, maps, mod_path, wet, fluid):
    stage = {
        'baseColorMap': f'{mod_path}/{folder}/t_{folder}_b.color.png',
        'normalMap': f'{mod_path}/{folder}/t_{folder}_nm.normal.png',
        'opacityMap': f'{mod_path}/{folder}/t_{folder}_o.data.png',
        'roughnessMap': f'{mod_path}/{folder}/t_{folder}_r{"_dry" if (fluid and not wet) else ""}.data.png',
    }
    if maps.get('ao') is not None:
        stage['ambientOcclusionMap'] = f'{mod_path}/{folder}/t_{folder}_ao.data.png'
    if wet:
        stage['baseColorFactor'] = [0.8, 0.8, 0.8, 1] if not fluid else [1, 1, 1, 1]
        stage['opacityFactor'] = 1.0
        if not fluid:
            stage['roughnessFactor'] = 0.4
    else:
        stage['baseColorFactor'] = [1, 1, 1, 1] if not fluid else [1.15, 1.1, 1.0, 1]
        stage['opacityFactor'] = 0.95 if not fluid else 0.7
    return {
        'name': name, 'mapTo': name, 'class': 'Material', 'persistentId': str(uuid.uuid5(uuid.NAMESPACE_URL, 'carsurfacefx/' + name)),
        'Stages': [stage, {}, {}, {}], 'annotation': 'NATURE', 'materialTag0': 'RoadAndPath', 'translucent': True, 'translucentZWrite': True, 'version': 1.5,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(os.path.dirname(__file__), '..', 'mod', 'art', 'surfacefx', 'marks'))
    ap.add_argument('--flip-green', action='store_true')
    ap.add_argument('--only', default='')
    args = ap.parse_args()
    out = os.path.abspath(args.out)
    mod_path = '/art/surfacefx/marks'
    mats, index = {}, []
    for name, (maker, length, width, note) in TYPES.items():
        if args.only and args.only not in name:
            continue
        maps = maker(args.flip_green)
        d = os.path.join(out, name)
        save(os.path.join(d, f't_{name}_b.color.png'), maps['color'], 'RGB')
        save(os.path.join(d, f't_{name}_o.data.png'), np.clip(maps['opacity'], 0, 1), 'L')
        save(os.path.join(d, f't_{name}_nm.normal.png'), maps['normal'], 'RGB')
        save(os.path.join(d, f't_{name}_r.data.png'), np.clip(maps['rough'], 0, 1), 'L')
        if name in FLUIDS:
            save(os.path.join(d, f't_{name}_r_dry.data.png'), np.clip(maps['rough_dry'], 0, 1), 'L')
        if maps.get('ao') is not None:
            save(os.path.join(d, f't_{name}_ao.data.png'), np.clip(maps['ao'], 0, 1), 'L')
        fluid = name in FLUIDS
        for wet in (False, True):
            mname = f'csfx_{name}_{"wet" if wet else "dry"}'
            mats[mname] = material(mname, name, name, maps, mod_path, wet, fluid)
        index.append({'type': name, 'dry': f'csfx_{name}_dry', 'wet': f'csfx_{name}_wet', 'textureLength': length, 'width': width, 'size': list(maps['size']), 'note': note, 'blob': fluid})
    json.dump(mats, open(os.path.join(out, 'main.materials.json'), 'w'), indent=1)
    json.dump({'types': index, 'normalConvention': 'OpenGL (green up)' if args.flip_green else 'DirectX (green down)'}, open(os.path.join(out, 'marks_index.json'), 'w'), indent=1)
    print('made', len(index), 'types,', len(mats), 'materials in', out)


if __name__ == '__main__':
    main()
