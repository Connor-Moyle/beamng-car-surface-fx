"""Covet mock-ups of the dirt rework: python tools/mock/covetdirt.py <covet.dae> <out folder>

The real covet.dae (paint material 'covet', second UV set, as bodydirt.lua reads it) goes through the real bodymap.lua, spraytrace.lua and rules.lua (LuaJIT, lupa). Three drives are run through
rules.dirtBuild (bodywear-rewrite d7252dd): a dirt road on a damp day (3 min of tarmac, then 4 min of dirt at 18 m/s, wet 0.3), a mud run (2 min at 14 m/s, wet 0.5) and a parked car in snow
(3 min of snowfall). The amounts become hits with bodymap.sample (the splat counts and sizes of PLACE in carSurfaceFx.lua), the hits are drawn on a 1024 x 1024 paint canvas with the textures of
mod/art/surfacefx/dirt (cakes at low places, speckle fans of the traced spray, the film and dust as tiled masks weighted by the rules' per-cell weights, rain streaks on the vertical faces in the
wet run, snow on flat sky-facing cells only), and the car is drawn from the canvas with a small orthographic z-buffer renderer. The wheels are not in covet.dae: they are drawn as plain tyres
at places taken from the body's bounds, so the arches and the spray origin are approximate. Pale dirt (dust, snow) is drawn as the palette canvas would lift it (a multiply on the base canvas
can only darken).
"""
import os
import sys
import time

import numpy as np
from lupa.luajit21 import LuaRuntime
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(HERE, '..', '..', 'mod', 'lua', 'ge', 'extensions').replace('\\', '/')
TEXD = os.path.join(HERE, '..', '..', 'mod', 'art', 'surfacefx', 'dirt')
dae, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
CV = 1024
PAINT = (0.52, 0.05, 0.07)

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path = '" + EXT + "/?.lua;' .. package.path")
lua.execute("function readFile(p) local f = io.open(p, 'rb') if not f then return nil end local s = f:read('*a') f:close() return s end")
lua.execute("log = function() end")
lua.globals().DAE = dae


def read_tris(mats):
    lua.globals().MATS = lua.table_from({m: True for m in mats})
    lua.execute("""
    TRIS = {}
    local wanted = setmetatable({}, { __index = function() return true end })
    local co = coroutine.create(function() require('carSurfaceFx/daeread').read(DAE, wanted, MATS, 1, TRIS) end)
    while coroutine.status(co) ~= 'dead' do local ok, err = coroutine.resume(co) if not ok then error(err) end end
    """)
    return int(lua.eval('#TRIS'))


def tris_arrays():
    n = int(lua.eval('#TRIS'))
    flat = lua.eval("(function() local o = {} for i, t in ipairs(TRIS) do for j = 1, 9 do o[#o + 1] = t.pos[j] end for j = 1, 6 do o[#o + 1] = t.uv[j] end end return o end)()")
    a = np.array([flat[i + 1] for i in range(n * 15)], np.float32).reshape(n, 15)
    return a[:, :9].reshape(n, 3, 3), a[:, 9:].reshape(n, 3, 2)


t0 = time.time()
read_tris(['covet'])
paint_pos, paint_uv = tris_arrays()
print('paint tris', len(paint_pos), '%.1fs' % (time.time() - t0))
other = []
for m, cls in (('covet_glass', 1), ('sealedbeam_glass', 1), ('sealedbeam', 2), ('covet_mechanical', 2), ('covet_lettering', 2), ('policeparts', 2)):
    try:
        read_tris([m])
        if int(lua.eval('#TRIS')) > 0:
            p, _ = tris_arrays()
            other.append((p, cls))
    except Exception as e:                                          # a material name the dae does not have
        print('skip', m, e)
x0, x1 = paint_pos[..., 0].min(), paint_pos[..., 0].max()
y0, y1 = paint_pos[..., 1].min(), paint_pos[..., 1].max()
z0, z1 = paint_pos[..., 2].min(), paint_pos[..., 2].max()
L = y1 - y0
WR = 0.31
WHEELS = [(0.72, y0 + 0.19 * L, WR + z0 * 0), (-0.72, y0 + 0.19 * L, WR), (0.72, y1 - 0.19 * L, WR), (-0.72, y1 - 0.19 * L, WR)]
print('body bounds x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f; wheels at y %.2f / %.2f' % (x0, x1, y0, y1, z0, z1, WHEELS[0][1], WHEELS[2][1]))
read_tris(['covet'])
lua.execute("WHEELS = {}")
for i, (x, y, z) in enumerate(WHEELS):
    lua.execute("WHEELS[%d] = { x = %s, y = %s, z = %s, r = %s, w = 0.2 }" % (i + 1, x, y, z, WR))
lua.execute("""
B = require('carSurfaceFx/bodymap'); S = require('carSurfaceFx/spraytrace'); R = require('carSurfaceFx/rules')
MAP = B.build(TRIS, WHEELS)
MAP.spray = S.bake(TRIS, WHEELS, { speed = 20, rays = 600 })
local seed = 77
function RND() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
function DRIVE(legs)
  local d = R.dirtNew()
  for _, l in ipairs(legs) do
    local t = 0
    while t < l.secs do d = R.dirtBuild(d, 0.5, l.r, l.speed, l.wet) t = t + 0.5 end
  end
  return d
end
""")
print('map cells', lua.eval('#MAP.list'), 'wheels', lua.eval('#MAP.wheels'))

SCENARIOS = {
    'dirtroad': "DRIVE({ { secs = 180, speed = 18, wet = 0.3, r = { road = 1 } }, { secs = 240, speed = 18, wet = 0.3, r = { loose = 1 } } })",
    'mud': "DRIVE({ { secs = 120, speed = 14, wet = 0.5, r = { mud = 1 } } })",
    'snow': "DRIVE({ { secs = 180, speed = 0, wet = 0, r = { snowing = 1 } } })",
}
PLACE = {'mud': (700, 0.035), 'dust': (180, 0.06), 'grime': (220, 0.05), 'snow': (90, 0.07)}


def amounts(name):
    lua.globals().SC = name
    return {k: float(lua.eval("(%s)['%s'] or 0" % (SCENARIOS[name], k))) for k in ('dust', 'mud', 'grime', 'snow')}


def weights(kind, opts=None):
    lua.globals().KIND = kind
    lua.execute("OPTS = %s" % ('{ maxH = %s, washH = 1 }' % opts if opts is not None else 'nil'))
    n = int(lua.eval('#MAP.list'))
    flat = lua.eval("(function() local o = {} for i, c in ipairs(MAP.list) do o[#o + 1] = c.gx o[#o + 1] = c.gy o[#o + 1] = B.RULES[KIND](MAP, c, nil, OPTS) end return o end)()")
    a = np.array([flat[i + 1] for i in range(n * 3)], np.float32).reshape(n, 3)
    g = np.zeros((int(lua.eval('B.N')),) * 2, np.float32)
    g[a[:, 1].astype(int), a[:, 0].astype(int)] = a[:, 2]
    return g


def hits(kind, n, wi=None, opts=None):
    lua.globals().KIND, lua.globals().NN, lua.globals().WI = kind, n, wi
    lua.execute("OPTS = %s" % ('{ maxH = %s, washH = 1 }' % opts if opts is not None else 'nil'))
    res = lua.eval("(function() local r = B.sample(MAP, KIND, NN, RND, WI, OPTS) local o = {} for i, s in ipairs(r) do o[i] = { s.u, s.v, s.s or 0.2, s.dx or 0, s.dy or 0, s.h or -1 } end return o end)()")
    return [tuple(res[i][j] for j in range(1, 7)) for i in range(1, len(res) + 1)]


def cell_height(u, v, hmap):
    N = hmap.shape[0]
    return hmap[min(N - 1, int(v * N)), min(N - 1, int(u * N))]


def maps():
    """per-cell maps of the body map (N x N): height 0..1, normal z and y, place x y z"""
    n = int(lua.eval('#MAP.list'))
    flat = lua.eval("(function() local o = {} for i, c in ipairs(MAP.list) do o[#o + 1] = c.gx o[#o + 1] = c.gy o[#o + 1] = c.h o[#o + 1] = c.nz o[#o + 1] = c.ny o[#o + 1] = c.px o[#o + 1] = c.py o[#o + 1] = c.pz end return o end)()")
    a = np.array([flat[i + 1] for i in range(n * 8)], np.float32).reshape(n, 8)
    N = int(lua.eval('B.N'))
    out = {k: np.zeros((N, N), np.float32) for k in ('h', 'nz', 'ny', 'px', 'py', 'pz')}
    out['h'][:] = 1.0
    gy, gx = a[:, 1].astype(int), a[:, 0].astype(int)
    for j, k in enumerate(('h', 'nz', 'ny', 'px', 'py', 'pz')):
        out[k][gy, gx] = a[:, 2 + j]
    out['on'] = np.zeros((N, N), np.float32)
    out['on'][gy, gx] = 1
    return out


def heightmap():
    m = maps()
    return m['h'], m['nz']


# ---------- textures and the canvas
def load(n):
    return np.asarray(Image.open(os.path.join(TEXD, n)).convert('RGBA'), np.float32) / 255


film_t, dust_t, speck_t, cakes_t, streak_t = (load(n) for n in ('film.png', 'dust.png', 'speckle.png', 'cakes.png', 'streaks.png'))


def tile(a, w, h, ox=0, oy=0):
    return np.tile(a, (h // a.shape[0] + 2, w // a.shape[1] + 2))[oy:oy + h, ox:ox + w]


def up(g):
    """a per-cell map to canvas size; cells off the car are filled from their neighbours first so the edges of the UV islands do not fade"""
    g = np.asarray(g, np.float32)
    return np.asarray(Image.fromarray(g).resize((CV, CV), Image.BILINEAR), np.float32).clip(0, None)


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def fnoise(n, beta, seed):
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((n, n)))
    fy, fx = np.meshgrid(np.fft.fftfreq(n), np.fft.fftfreq(n), indexing='ij')
    r = np.sqrt(fx * fx + fy * fy); r[0, 0] = 1
    a = np.real(np.fft.ifft2(f / r ** (beta / 2)))
    return (a - a.min()) / (a.max() - a.min())


def sprite(img, angle, sx, sy=None):
    sy = sx if sy is None else sy
    im = Image.fromarray((img * 255).astype(np.uint8), 'RGBA')
    im = im.resize((max(1, int(im.width * sx)), max(1, int(im.height * sy))), Image.LANCZOS).rotate(angle, expand=True, resample=Image.BICUBIC)
    return np.asarray(im, np.float32) / 255


def put(cov, rgb, spr, x, y, col=None):
    """union a sprite's alpha into cov; where it wins, rgb gets col * the sprite's shade (cakes) or just col"""
    h, w = spr.shape[:2]
    xa, ya = int(x - w / 2), int(y - h / 2)
    cx0, cy0, cx1, cy1 = max(0, xa), max(0, ya), min(CV, xa + w), min(CV, ya + h)
    if cx1 <= cx0 or cy1 <= cy0:
        return
    sub = spr[cy0 - ya:cy1 - ya, cx0 - xa:cx1 - xa]
    a = sub[..., 3]
    if rgb is not None:
        m = (a > cov[cy0:cy1, cx0:cx1])[..., None]
        rgb[cy0:cy1, cx0:cx1] = np.where(m, np.clip(np.array(col, np.float32) * sub[..., :1] * 1.6, 0, 1), rgb[cy0:cy1, cx0:cx1])
    cov[cy0:cy1, cx0:cx1] = 1 - (1 - cov[cy0:cy1, cx0:cx1]) * (1 - a)


# what each drive looks like (the amounts come from the rules; these are how the look is set for it)
LOOK = {
    'dirtroad': dict(crust=0.55, dryshare=0.65, wake=(0.40, 0.35, 0.29), wake_k=0.95, film=1.0, streak=0.25, splash=0.5, dust=1.0, cakes=0.7, haze=1.0),
    'mud':      dict(crust=1.0, dryshare=0.08, wake=(0.20, 0.15, 0.11), wake_k=1.0, film=0.0, streak=1.0, splash=1.0, dust=0.0, cakes=1.0, haze=0.0),
    'snow':     dict(crust=0, dryshare=0, wake=(0, 0, 0), wake_k=0, film=0, streak=0, splash=0, dust=0, cakes=0, haze=0),
}
WET, DRY = np.array([0.19, 0.14, 0.10], np.float32), np.array([0.40, 0.34, 0.27], np.float32)
CAKE_DRY = np.array([0.36, 0.30, 0.24], np.float32)


def canvas(name):
    rng = np.random.default_rng(11)
    am = amounts(name)
    lk = LOOK[name]
    print(name, {k: round(v, 3) for k, v in am.items()})
    m = maps()
    H_, NZ, NY = m['h'], m['nz'], m['ny']
    cov = {k: np.zeros((CV, CV), np.float32) for k in ('film', 'dust', 'speck', 'cake', 'streak', 'snow', 'mudfilm', 'wake', 'crust', 'haze', 'wet')}
    cake_rgb = np.zeros((CV, CV, 3), np.float32)
    crust_rgb = np.zeros((CV, CV, 3), np.float32)
    hh, nzu, nyu = up(H_), up(NZ), up(NY)
    n1, n2, n3 = fnoise(CV, 2.2, 3), fnoise(CV, 1.4, 4), fnoise(CV, 3.0, 5)
    # --- road film: an even grey-brown haze over the lower half, fading upward; dust lifts the paint a little so it reads dull
    if lk['film'] > 0:
        w = np.clip((0.95 - hh) / 0.95, 0, 1) ** 0.75
        base = tile(film_t[..., 3], CV, CV, 31, 7)
        cov['film'] = np.clip(w * (0.55 + 0.7 * base) * (0.7 + 0.3 * n1) * lk['film'], 0, 1)
    # --- an even light dust haze over the whole body (roof, doors above the swage line, pillars), a little heavier low: dulls the paint
    if lk['haze'] > 0:
        cov['haze'] = np.clip((0.42 + 0.35 * np.clip(1 - hh / 1.2, 0, 1)) * (0.8 + 0.2 * n1) * min(1, am['dust']) * lk['haze'], 0, 1)
    # --- the wake: the tailgate, the rear bumper and the rear glass, thickest at the bottom
    if lk['wake_k'] > 0:
        wk = smooth(nyu, 0.12, 0.55) * np.clip(1 - hh * 0.95, 0, 1) ** 0.6
        cov['wake'] = np.clip(wk * 1.25 * (0.62 + 0.38 * n2) , 0, 1)
    # --- where the heavy mud is: arch lips, the panel right behind each wheel, the sills, the bumper's lower edge
    px, py, pz = up(m['px']), up(m['py']), up(m['pz'])
    crustW = np.zeros((CV, CV), np.float32)
    for (wx, wy, wz) in WHEELS:
        d = np.sqrt((px - wx) ** 2 + (py - wy) ** 2 + (pz - wz) ** 2)
        lip = np.exp(-((d - (WR + 0.07)) ** 2) / (2 * 0.11 ** 2))
        dy = (py - wy) * (1 if wy < 0 else 1)                       # behind the wheel = toward the back of the car (the car goes forward, -y)
        dx = np.abs(px - wx)
        beh = np.where((dy > -0.1) & (dy < 1.0) & (dx < 0.7), np.exp(-np.maximum(dy, 0) / 0.55), 0) * np.exp(-np.maximum(pz - wz, 0) / 0.45)
        crustW = np.maximum(crustW, np.maximum(lip * np.exp(-np.maximum(pz - 0.15, 0) / 0.8), beh))
    sill = np.where(hh < 0.2, 1.0, np.exp(-(hh - 0.2) / 0.12)) * (np.abs(nzu) < 0.6)
    bump = np.where((nyu > 0.3) & (hh < 0.22), 1.0, 0)
    crustW = np.maximum(crustW, np.maximum(0.7 * sill, 0.85 * bump))
    if lk['crust'] > 0 and am['mud'] > 0:
        A = lk['crust'] * min(1, am['mud'])
        cov['crust'] = smooth(crustW * (0.55 + 0.9 * A) - 0.38 * (n1 - 0.5) - 0.20 * (n3 - 0.5) - 0.18, 0.0, 0.20)
        dry = smooth(n2 + (lk['dryshare'] - 0.5) * 0.9, 0.42, 0.62)       # patches that have dried lighter
        shade = (0.65 + 0.9 * (n3 - 0.5) + 0.35 * (fnoise(CV, 1.0, 6) - 0.5)).clip(0.35, 1.3)
        cov['wet'] = cov['crust'] * (1 - dry)
        crust_rgb[:] = (WET[None, None, :] * (1 - dry[..., None]) + DRY[None, None, :] * dry[..., None]) * shade[..., None]
        # the splash haze under everything, heaviest low and behind the wheels
        cov['mudfilm'] = np.clip(tile(film_t[..., 3], CV, CV, 90, 40) * 0.5 + 0.55, 0, 1) * np.clip(crustW * 1.2 + np.exp(-hh / 0.35) * 0.35, 0, 1) * lk['splash']
        # clods of varied size and shape on top of the crust and beyond it: more of the small, merging near the wheels
        n = int(am['mud'] * PLACE['mud'][0] * lk['cakes'])
        lua.execute("SPRAY = MAP.spray MAP.spray = nil")
        ch = []
        for wi in (1, 2, 3, 4):
            ch += hits('mud', int(n * 0.9), wi)
        lua.execute("MAP.spray = SPRAY")
        for (u, v, s, dx, dy, _) in ch:
            if cell_height(u, v, H_) > 0.5:
                continue
            for k in range(1 + int(rng.random() < 0.6) + int(rng.random() < 0.3)):     # the clod and its neighbours
                ox, oy = (rng.normal(0, 7), rng.normal(0, 7)) if k else (0.0, 0.0)
                dry = rng.random() < lk['dryshare']
                vi = int(rng.integers(0, 4))
                cell = cakes_t[(128 if dry else 0):(256 if dry else 128), vi * 128:(vi + 1) * 128]
                size = s * CV * float(np.clip(np.exp(rng.normal(np.log(0.045), 0.55)), 0.015, 0.15))     # 1.5 to 15 cm, mostly small
                st = rng.uniform(0.7, 1.45)
                col = (CAKE_DRY if dry else WET * 1.25) * rng.uniform(0.85, 1.15)
                put(cov['cake'], cake_rgb, sprite(cell, rng.uniform(0, 360), size / 128 * st, size / 128 / st), u * CV + ox, v * CV + oy, col)
        # fans thrown back from each tyre (the traced spray)
        for wi in (1, 2, 3, 4):
            for (u, v, s, dx, dy, _) in hits('mud', int(n / 4 * 0.5), wi):
                k = int(rng.integers(0, 4))
                cell = speck_t[(k // 2) * 256:(k // 2) * 256 + 256, (k % 2) * 256:(k % 2) * 256 + 256]
                put(cov['speck'], None, sprite(cell, -90 - np.degrees(np.arctan2(dy, dx)), s * CV * rng.uniform(0.35, 0.6) / 256), u * CV, v * CV)
        # runs down the vertical panels from the dirty areas
        if lk['streak'] > 0:
            wv = np.clip(crustW * 1.3 + 0.25, 0, 1) * (1 - np.clip(np.abs(nzu), 0, 1)) * np.clip(1.15 - hh, 0, 1)
            cov['streak'] = np.clip(tile(streak_t[..., 3], CV, CV, 0, 200) * 1.6, 0, 1) * wv * lk['streak']
    if lk['dust'] > 0 and am['dust'] > 0:
        w = up(weights('dust', am['dust'] ** 0.7))
        cov['dust'] = np.clip(tile(dust_t[..., 3], CV, CV, 5, 77) * 1.3, 0, 1) * np.clip(w / 1.0, 0, 1) * 0.9
    if am['snow'] > 0:
        w = up(weights('snow'))
        cov['snow'] = smooth(np.clip(w, 0, 1) * min(1, am['snow'] * 1.15) - 0.25 * (n3 - 0.5) - 0.12, 0.0, 0.18)
    return (cov, cake_rgb, crust_rgb, dict(lk, wet=cov['wet']))


def compose(pack):
    cov, cake_rgb, crust_rgb, lk = pack
    img = np.zeros((CV, CV, 3), np.float32) + np.array(PAINT, np.float32)

    def mult(img, c, col, k):
        return img * (1 - (c * k)[..., None] * (1 - np.array(col, np.float32)))
    img = mult(img, cov['haze'], (0.62, 0.58, 0.52), 0.55)
    img = img + (np.array([0.70, 0.64, 0.55]) - img) * (cov['haze'] * 0.38)[..., None]
    # film: dull, dusty paint (a multiply by grey-brown and a lift toward pale)
    img = mult(img, cov['film'], (0.50, 0.46, 0.40), 0.92)
    img = img + (np.array([0.66, 0.60, 0.52]) - img) * (cov['film'] * 0.30)[..., None]
    img = mult(img, cov['wake'], lk['wake'], lk['wake_k'])
    img = img + (np.array([0.55, 0.50, 0.42]) - img) * (cov['wake'] * 0.12 * (1 if lk['dust'] else 0))[..., None]
    img = mult(img, cov['mudfilm'], (0.30, 0.22, 0.15), 0.9)
    img = mult(img, cov['streak'], (0.28, 0.21, 0.15), 0.95)
    img = mult(img, cov['speck'], (0.26, 0.19, 0.13), 0.97)
    c = cov['crust'][..., None]
    img = img * (1 - c) + crust_rgb * c
    c = cov['cake'][..., None]
    img = img * (1 - c) + cake_rgb * c
    img = img + (np.array([0.80, 0.72, 0.58]) - img) * (cov['dust'] * 0.45)[..., None]
    sn = cov['snow'][..., None]
    img = img * (1 - sn) + np.array([0.93, 0.95, 0.98]) * sn
    dirty = np.clip(cov['haze'] * 0.5 + cov['film'] * 0.7 + cov['wake'] + cov['mudfilm'] + cov['speck'] + cov['crust'] + cov['cake'] + cov['dust'] * 0.6 + cov['snow'] + cov['streak'], 0, 1)
    return np.clip(img, 0, 1), dirty, lk


# ---------- the renderer
def cylinders():
    tris = []
    for (wx, wy, wz) in WHEELS:
        side = 1 if wx > 0 else -1
        k = 28
        for i in range(k):
            a0, a1 = 2 * np.pi * i / k, 2 * np.pi * (i + 1) / k
            for xs, xe in ((wx - side * 0.10 + 0.0, wx + side * 0.10),):
                p = lambda x, a, r: (x, wy + r * np.cos(a), wz + r * np.sin(a))
                for (r0, r1) in ((WR, WR),):
                    q = [p(xs, a0, r0), p(xe, a0, r1), p(xe, a1, r1), p(xs, a1, r0)]
                    tris += [(q[0], q[1], q[2]), (q[0], q[2], q[3])]
                for x in (xs, xe):
                    tris.append(((x, wy, wz), p(x, a0, WR), p(x, a1, WR)))
    return np.array(tris, np.float32)


def normals(pos):
    n = np.cross(pos[:, 1] - pos[:, 0], pos[:, 2] - pos[:, 0])
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)


def render(view, albedo, dirty, lk=None, size=(1500, 820), ss=2):
    W, H = size[0] * ss, size[1] * ss
    c = np.array(view['cam'], np.float32); c /= np.linalg.norm(c)
    f = -c
    r = np.cross(f, [0, 0, 1]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    allp = [paint_pos] + [p for p, _ in other] + [cylinders()]
    cls = np.concatenate([np.zeros(len(paint_pos), np.int8)] + [np.full(len(p), k, np.int8) for p, k in other] + [np.full(len(allp[-1]), 3, np.int8)])
    P = np.concatenate(allp)
    uv = np.concatenate([paint_uv, np.zeros((len(P) - len(paint_uv), 3, 2), np.float32)])
    ctr = np.array(view['target'], np.float32)
    q = P - ctr
    sx, sy, dz = q @ r, -(q @ u), q @ c
    scale = view['scale'] * ss
    X, Y = sx * scale + W / 2, sy * scale + H / 2 + view.get('dy', 0) * ss
    zb = np.full((H, W), -1e9, np.float32)
    tid = np.full((H, W), -1, np.int32)
    B1 = np.zeros((H, W), np.float32); B2 = np.zeros((H, W), np.float32)
    for i in range(len(P)):
        xs, ys, zs = X[i], Y[i], dz[i]
        ax, bx = int(max(0, np.floor(xs.min()))), int(min(W - 1, np.ceil(xs.max())))
        ay, by = int(max(0, np.floor(ys.min()))), int(min(H - 1, np.ceil(ys.max())))
        if bx < ax or by < ay:
            continue
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(d) < 1e-9:
            continue
        gy, gx = np.mgrid[ay:by + 1, ax:bx + 1]
        px, py = gx + 0.5, gy + 0.5
        w0 = ((ys[1] - ys[2]) * (px - xs[2]) + (xs[2] - xs[1]) * (py - ys[2])) / d
        w1 = ((ys[2] - ys[0]) * (px - xs[2]) + (xs[0] - xs[2]) * (py - ys[2])) / d
        w2 = 1 - w0 - w1
        m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not m.any():
            continue
        z = w0 * zs[0] + w1 * zs[1] + w2 * zs[2]
        sub = zb[ay:by + 1, ax:bx + 1]
        m &= z > sub
        if not m.any():
            continue
        sub[m] = z[m]
        tid[ay:by + 1, ax:bx + 1][m] = i
        B1[ay:by + 1, ax:bx + 1][m] = w1[m]
        B2[ay:by + 1, ax:bx + 1][m] = w2[m]
    nrm = normals(P)
    nrm = np.where((nrm @ c)[:, None] < 0, -nrm, nrm)
    has = tid >= 0
    t = np.where(has, tid, 0)
    n = nrm[t]
    cl = cls[t]
    uvp = uv[t][..., 0, :] + B1[..., None] * (uv[t][..., 1, :] - uv[t][..., 0, :]) + B2[..., None] * (uv[t][..., 2, :] - uv[t][..., 0, :])
    ix = np.clip((uvp[..., 0] * CV).astype(int), 0, CV - 1)
    iy = np.clip((uvp[..., 1] * CV).astype(int), 0, CV - 1)
    alb = albedo[iy, ix]
    wz = (1 - B1 - B2) * P[t][..., 0, 2] + B1 * P[t][..., 1, 2] + B2 * P[t][..., 2, 2]
    drt = dirty[iy, ix]
    col = np.where((cl == 0)[..., None], alb, np.where((cl == 1)[..., None], np.array([0.05, 0.07, 0.09], np.float32), np.where((cl == 3)[..., None], np.array([0.05, 0.05, 0.055], np.float32), np.array([0.16, 0.16, 0.17], np.float32))))
    if lk is not None and lk['wake_k'] > 0:                          # the glass gets the wake too (it has its own canvas in the game): rear-facing, thickest at the bottom
        wk = smooth(n[..., 1], 0.12, 0.55) * np.clip(1 - (wz - z0) / (z1 - z0) * 0.95, 0, 1) ** 0.6 * 0.9
        col = np.where((cl == 1)[..., None], col * (1 - wk[..., None]) + np.array(lk['wake'], np.float32) * 1.25 * wk[..., None], col)
    L = np.array([0.45, 0.55, 0.8], np.float32); L /= np.linalg.norm(L)
    nl = np.clip(n @ L, 0, 1)
    sky = (n[..., 2] * 0.5 + 0.5)
    shade = 0.28 + 0.30 * sky + 0.70 * nl
    hv = L + c; hv /= np.linalg.norm(hv)
    wetv = lk['wet'][iy, ix] if lk is not None and 'wet' in lk else 0
    spec = np.clip(n @ hv, 0, 1) ** 50 * 0.55 * np.where(cl == 0, np.maximum(1 - drt, wetv * 0.9), np.where(cl == 1, 1.2, 0.1))
    rgb = col * shade[..., None] + spec[..., None]
    # a ground plane under the car: grey, darker near the car (a soft contact shadow), light toward the horizon
    ys_ = (np.arange(H) / H)[:, None, None]
    bg = np.array([0.55, 0.57, 0.6], np.float32) * (0.75 + 0.25 * ys_) * np.ones((1, W, 1), np.float32)
    zfloor = z0 - 0.0
    rgb = np.where(has[..., None], rgb, bg)
    img = (np.clip(rgb, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8)
    im = Image.fromarray(img).resize(size, Image.LANCZOS)
    return im


def views():
    cx, cy, cz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
    return {
        'rear34': {'cam': (0.62, 0.78, 0.30), 'target': (cx, cy, cz), 'scale': 330},
        'side': {'cam': (1.0, 0.0, 0.05), 'target': (cx, cy, cz), 'scale': 330},
        'top34': {'cam': (0.55, -0.55, 0.62), 'target': (cx, cy, cz + 0.2), 'scale': 330},
    }


def main():
    V = views()
    shots = [('clean', 'rear34'), ('dirtroad', 'rear34'), ('dirtroad', 'side'), ('mud', 'rear34'), ('mud', 'side'), ('snow', 'top34')]
    cache = {}
    ims = {}
    for name, view in shots:
        if name == 'clean':
            albedo = np.zeros((CV, CV, 3), np.float32) + np.array(PAINT, np.float32)
            dirty = np.zeros((CV, CV), np.float32)
            lk_ = None
        else:
            if name not in cache:
                cache[name] = compose(canvas(name))
                Image.fromarray((cache[name][0] * 255).astype(np.uint8)).save(os.path.join(out, 'canvas_%s.png' % name))
            albedo, dirty, lk_ = cache[name]
        t0 = time.time()
        im = render(V[view], albedo, dirty, lk_)
        fn = os.path.join(out, 'covet_%s_%s.png' % (name, view))
        im.save(fn)
        ims[(name, view)] = im
        print('wrote', fn, '%.0fs' % (time.time() - t0))
    sheet = Image.new('RGB', (1500 * 2 + 30, (820 + 26) * 3 + 10), (24, 24, 26))
    dr = ImageDraw.Draw(sheet)
    layout = [('clean', 'rear34', 'clean (reference)'), ('dirtroad', 'rear34', 'after a dirt road, damp: rear 3/4'), ('dirtroad', 'side', 'after a dirt road: side and sills'),
              ('mud', 'rear34', 'after a mud run: rear 3/4'), ('mud', 'side', 'after a mud run: side and sills'), ('snow', 'top34', 'parked in snow: roof and bonnet')]
    for i, (n, v, label) in enumerate(layout):
        x, y = 10 + (i % 2) * (1500 + 10), 6 + (i // 2) * (820 + 26)
        sheet.paste(ims[(n, v)], (x, y + 18))
        dr.text((x, y), label, fill=(255, 255, 255))
    sheet.save(os.path.join(out, 'covet_dirt_sheet.png'))
    print('sheet written')


if __name__ == '__main__':
    main()
