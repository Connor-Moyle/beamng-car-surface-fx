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


def heightmap():
    n = int(lua.eval('#MAP.list'))
    flat = lua.eval("(function() local o = {} for i, c in ipairs(MAP.list) do o[#o + 1] = c.gx o[#o + 1] = c.gy o[#o + 1] = c.h o[#o + 1] = c.nz end return o end)()")
    a = np.array([flat[i + 1] for i in range(n * 4)], np.float32).reshape(n, 4)
    N = int(lua.eval('B.N'))
    h, nz = np.full((N, N), 1.0, np.float32), np.zeros((N, N), np.float32)
    h[a[:, 1].astype(int), a[:, 0].astype(int)] = a[:, 2]
    nz[a[:, 1].astype(int), a[:, 0].astype(int)] = a[:, 3]
    return h, nz


# ---------- textures and the canvas
def load(n):
    return np.asarray(Image.open(os.path.join(TEXD, n)).convert('RGBA'), np.float32) / 255


film_t, dust_t, speck_t, cakes_t, streak_t = (load(n) for n in ('film.png', 'dust.png', 'speckle.png', 'cakes.png', 'streaks.png'))


def tile(a, w, h, ox=0, oy=0):
    return np.tile(a, (h // a.shape[0] + 2, w // a.shape[1] + 2))[oy:oy + h, ox:ox + w]


def up(g):
    return np.asarray(Image.fromarray(g).resize((CV, CV), Image.BICUBIC), np.float32).clip(0, None)


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def sprite(img, angle, scale):
    im = Image.fromarray((img * 255).astype(np.uint8), 'RGBA')
    im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS).rotate(angle, expand=True, resample=Image.BICUBIC)
    return np.asarray(im, np.float32) / 255


def put(cov, shade, spr, x, y):
    h, w = spr.shape[:2]
    xa, ya = int(x - w / 2), int(y - h / 2)
    cx0, cy0, cx1, cy1 = max(0, xa), max(0, ya), min(CV, xa + w), min(CV, ya + h)
    if cx1 <= cx0 or cy1 <= cy0:
        return
    sub = spr[cy0 - ya:cy1 - ya, cx0 - xa:cx1 - xa]
    a = sub[..., 3]
    if shade is not None:
        m = a > cov[cy0:cy1, cx0:cx1]
        shade[cy0:cy1, cx0:cx1] = np.where(m, sub[..., 0], shade[cy0:cy1, cx0:cx1])
    cov[cy0:cy1, cx0:cx1] = 1 - (1 - cov[cy0:cy1, cx0:cx1]) * (1 - a)


def canvas(name):
    rng = np.random.default_rng(11)
    am = amounts(name)
    print(name, {k: round(v, 3) for k, v in am.items()})
    hmap, nzmap = heightmap()
    cov = {k: np.zeros((CV, CV), np.float32) for k in ('film', 'dust', 'speck', 'cake', 'streak', 'snow', 'mudfilm')}
    cake_shade = np.ones((CV, CV), np.float32)
    if am['grime'] > 0:
        w = up(weights('grime'))
        cov['film'] = tile(film_t[..., 3], CV, CV, 31, 7) * np.clip(w / 1.6, 0, 1) * min(1, am['grime'] / 0.35 + 0.25)
    if am['dust'] > 0:
        mh = am['dust'] ** 0.7
        w = up(weights('dust', mh))
        cov['dust'] = tile(dust_t[..., 3], CV, CV, 5, 77) * np.clip(w / 1.0, 0, 1) * min(1, 0.3 + am['dust'])
    if am['mud'] > 0:
        n = int(am['mud'] * PLACE['mud'][0])
        dryshare = 0.45 if name == 'dirtroad' else 0.15
        lua.execute("SPRAY = MAP.spray MAP.spray = nil")           # the rules' own places (sills, the panel behind each wheel, arch lips, bumper edge) for the clods
        cov['mudfilm'] = tile(film_t[..., 3], CV, CV, 90, 40) * np.clip(up(weights('mud')) / 1.1, 0, 1) * min(1, am['mud'])   # the splash haze under the clods
        cakehits = []
        for wi in (1, 2, 3, 4):
            cakehits += hits('mud', int(n * 0.6), wi)
        lua.execute("MAP.spray = SPRAY")
        for (u, v, s, dx, dy, _) in cakehits:
            if cell_height(u, v, hmap) > 0.42:
                continue
            dry = 1 if rng.random() < dryshare else 0
            vi = int(rng.integers(0, 4))
            cell = cakes_t[dry * 128:(dry + 1) * 128, vi * 128:(vi + 1) * 128]
            size = s * CV * rng.uniform(0.05, 0.10)                  # 5 to 10 cm
            put(cov['cake'], cake_shade, sprite(cell, rng.uniform(0, 360), size / 128), u * CV, v * CV)
        for wi in (1, 2, 3, 4):                                      # the traced spray: fans along the throw
            for (u, v, s, dx, dy, _) in hits('mud', int(n / 4 * 0.35), wi):
                k = int(rng.integers(0, 4))
                cell = speck_t[(k // 2) * 256:(k // 2) * 256 + 256, (k % 2) * 256:(k % 2) * 256 + 256]
                put(cov['speck'], None, sprite(cell, -90 - np.degrees(np.arctan2(dy, dx)), s * CV * rng.uniform(0.22, 0.36) / 256), u * CV, v * CV)
        if name == 'mud':                                             # after rain a mud run runs: streaks below the dirty vertical panels
            wv = up(weights('mud')) * (1 - np.clip(up(nzmap), 0, 1))
            cov['streak'] = tile(streak_t[..., 3], CV, CV, 0, 200) * np.clip(wv / 0.6, 0, 1) * 0.7
    if am['snow'] > 0:
        w = up(weights('snow'))
        nz = fnoise(CV, 3.0, 9)
        cov['snow'] = smooth(np.clip(w, 0, 1) * min(1, am['snow'] * 1.15) - 0.25 * (nz - 0.5) - 0.12, 0.0, 0.18)
    return cov, cake_shade


def fnoise(n, beta, seed):
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((n, n)))
    fy, fx = np.meshgrid(np.fft.fftfreq(n), np.fft.fftfreq(n), indexing='ij')
    r = np.sqrt(fx * fx + fy * fy); r[0, 0] = 1
    a = np.real(np.fft.ifft2(f / r ** (beta / 2)))
    return (a - a.min()) / (a.max() - a.min())


def compose(cov, cake_shade):
    img = np.zeros((CV, CV, 3), np.float32) + np.array(PAINT, np.float32)

    def mult(img, c, col, k):
        return img * (1 - (c * k)[..., None] * (1 - np.array(col, np.float32)))
    img = mult(img, cov['film'], (0.52, 0.48, 0.42), 0.8)
    img = mult(img, cov['mudfilm'], (0.34, 0.25, 0.17), 0.9)
    img = mult(img, cov['streak'], (0.40, 0.32, 0.25), 0.9)
    img = mult(img, cov['speck'], (0.33, 0.24, 0.16), 0.95)
    mudc = np.array([0.40, 0.27, 0.16], np.float32)
    c = cov['cake'][..., None]
    img = img * (1 - c) + c * np.clip(mudc * cake_shade[..., None] * 1.25, 0, 1)
    dust = cov['dust'][..., None] * 0.55
    img = img + (np.array([0.80, 0.72, 0.58]) - img) * dust
    sn = cov['snow'][..., None]
    img = img * (1 - sn) + np.array([0.93, 0.95, 0.98]) * sn
    dirty = np.clip(cov['film'] * 0.5 + cov['mudfilm'] + cov['speck'] + cov['cake'] + cov['dust'] * 0.6 + cov['snow'] + cov['streak'], 0, 1)
    return np.clip(img, 0, 1), dirty


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


def render(view, albedo, dirty, size=(1500, 820), ss=2):
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
    drt = dirty[iy, ix]
    col = np.where((cl == 0)[..., None], alb, np.where((cl == 1)[..., None], np.array([0.05, 0.07, 0.09], np.float32), np.where((cl == 3)[..., None], np.array([0.05, 0.05, 0.055], np.float32), np.array([0.16, 0.16, 0.17], np.float32))))
    L = np.array([0.45, 0.55, 0.8], np.float32); L /= np.linalg.norm(L)
    nl = np.clip(n @ L, 0, 1)
    sky = (n[..., 2] * 0.5 + 0.5)
    shade = 0.28 + 0.30 * sky + 0.70 * nl
    hv = L + c; hv /= np.linalg.norm(hv)
    spec = np.clip(n @ hv, 0, 1) ** 50 * 0.55 * np.where(cl == 0, 1 - drt, np.where(cl == 1, 1.2, 0.1))
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
        else:
            if name not in cache:
                cov, shade = canvas(name)
                cache[name] = compose(cov, shade)
                Image.fromarray((cache[name][0] * 255).astype(np.uint8)).save(os.path.join(out, 'canvas_%s.png' % name))
            albedo, dirty = cache[name]
        t0 = time.time()
        im = render(V[view], albedo, dirty)
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
