"""Mock-ups of where the dirt lands on a real car (default: the vivace): the real .dae read by carSurfaceFx/daeread.lua, the real body map and rules of bodymap.lua and the
spray hits of spraytrace.lua, run in LuaJIT (lupa), then drawn on the paint texture and as plain side, top and rear views.

    python tools/mock/dirtmap.py <vivace.dae> <out folder> [n splats]

Outputs: texture_<kind>.png (the splats on the texture's UV islands), views_<kind>.png (side from the left, top and rear), compare_mud_views.png and compare_mud_texture.png (the old
wheel-distance rule against the traced spray). The wheels are given in the script for the vivace (from its hub meshes); other cars need their own list.
"""
import os
import sys
import time

import numpy as np
from lupa.luajit21 import LuaRuntime
from PIL import Image, ImageDraw

dae = sys.argv[1]
out = sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 500
os.makedirs(out, exist_ok=True)
ext = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'mod', 'lua', 'ge', 'extensions').replace('\\', '/')
PAINT = 'vivace'
WHEELS = [(0.70, -1.315, 0.32, 0.31), (-0.70, -1.315, 0.32, 0.31), (0.70, 1.325, 0.32, 0.31), (-0.70, 1.325, 0.32, 0.31)]   # x left, y back, z up, radius

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path = '" + ext + "/?.lua;' .. package.path")
lua.execute("function readFile(p) local f = io.open(p, 'rb') if not f then return nil end local s = f:read('*a') f:close() return s end")
lua.execute("log = function() end")
lua.globals().DAE = dae
lua.globals().PAINT = PAINT
t0 = time.time()
tris = lua.execute("""
local read = require('carSurfaceFx/daeread').read
local tris = {}
local wanted = setmetatable({}, { __index = function() return true end })
local co = coroutine.create(function() read(DAE, wanted, { [PAINT] = true }, 1, tris) end)
while coroutine.status(co) ~= 'dead' do local ok, err = coroutine.resume(co) if not ok then error(err) end end
return tris
""")
n_tris = len(tris)
print('paint triangles:', n_tris, '%.1f s' % (time.time() - t0))
lua.globals().TRIS = tris
lua.execute("WHEELS = {}")
for i, (x, y, z, r) in enumerate(WHEELS):
    lua.execute("WHEELS[%d] = { x = %s, y = %s, z = %s, r = %s, w = 0.2 }" % (i + 1, x, y, z, r))
lua.execute("""
B = require('carSurfaceFx/bodymap')
S = require('carSurfaceFx/spraytrace')
MAP = B.build(TRIS, WHEELS)
local seed = 4242
function RND() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
""")
print('map cells:', lua.eval('#MAP.list'))
t0 = time.time()
lua.execute("BAKE = S.bake(TRIS, WHEELS, { speed = 18, rays = 600 })")
print('spray bake: %.1f s' % (time.time() - t0))
rates = lua.eval("(function() local r = {} for i, v in pairs(S.hitRate(BAKE)) do r[i] = v end return r end)()")
print('hit rates:', [round(rates[i], 2) for i in range(1, 5)])


def pairs_of(res):
    return [(res[i][1], res[i][2]) for i in range(1, len(res) + 1)]


def samples(kind, n):
    lua.globals().KIND, lua.globals().NN = kind, n
    return pairs_of(lua.eval("(function() local r = B.sample(MAP, KIND, NN, RND, nil) local o = {} for i, s in ipairs(r) do o[i] = { s.u, s.v } end return o end)()"))


def traced(n):
    lua.globals().NN = n
    return pairs_of(lua.eval("(function() local r = S.sample(BAKE, nil, NN, RND) local o = {} for i, s in ipairs(r) do o[i] = { s.u, s.v } end return o end)()"))


cells = {}
for i in range(1, int(lua.eval('#MAP.list')) + 1):
    c = lua.eval('MAP.list[%d]' % i)
    cells[(int(c['gx']), int(c['gy']))] = (c['px'], c['py'], c['pz'])
NB = int(lua.eval('B.N'))


def place(u, v):
    return cells.get((int(u * NB), int(v * NB)))


pos = np.array([[tris[i]['pos'][j] for j in range(1, 10)] for i in range(1, n_tris + 1)])
pts3 = pos.reshape(-1, 3)
uvs = np.array([[tris[i]['uv'][j] for j in range(1, 7)] for i in range(1, n_tris + 1)])

TEX = 768


def texture_image(points, color, title):
    im = Image.new('RGB', (TEX, TEX), (28, 28, 30))
    dr = ImageDraw.Draw(im)
    for t in uvs[:: max(1, len(uvs) // 40000)]:
        dr.polygon([(t[0] * TEX, t[1] * TEX), (t[2] * TEX, t[3] * TEX), (t[4] * TEX, t[5] * TEX)], outline=(70, 70, 76))
    for u, v in points:
        dr.ellipse([u * TEX - 2, v * TEX - 2, u * TEX + 2, v * TEX + 2], fill=color)
    dr.text((8, 6), title, fill=(255, 255, 255))
    return im


VW, VH = 520, 300


def views_image(points3, color, title):
    im = Image.new('RGB', (VW * 3 + 40, VH + 70), (24, 24, 26))
    dr = ImageDraw.Draw(im)
    x0, x1 = pts3[:, 0].min(), pts3[:, 0].max()
    y0, y1 = pts3[:, 1].min(), pts3[:, 1].max()
    z0, z1 = pts3[:, 2].min(), pts3[:, 2].max()

    def proj(view, p):
        x, y, z = p
        if view == 'side':                                    # from the left (+x): the front of the car at the left of the picture
            return 10 + (y - y0) / (y1 - y0) * (VW - 20), 50 + (z1 - z) / (z1 - z0) * (VH - 30)
        if view == 'top':
            return 20 + VW + 10 + (y - y0) / (y1 - y0) * (VW - 20), 50 + (x1 - x) / (x1 - x0) * (VH - 30)
        return 30 + 2 * VW + 20 + (x1 - x) / (x1 - x0) * (VW - 20) * 0.7 + 60, 50 + (z1 - z) / (z1 - z0) * (VH - 30)

    sub = pts3[:: max(1, len(pts3) // 60000)]
    for view in ('side', 'top', 'rear'):
        for p in sub:
            a, b = proj(view, p)
            dr.point((a, b), fill=(88, 88, 94))
        for (wx, wy, wz, wr) in WHEELS:
            a, b = proj(view, (wx, wy, wz))
            dr.ellipse([a - 4, b - 4, a + 4, b + 4], outline=(120, 200, 255))
        for p in points3:
            a, b = proj(view, p)
            dr.ellipse([a - 1.8, b - 1.8, a + 1.8, b + 1.8], fill=color)
    dr.text((10, 6), title + '   (side from the left, front at the left; top, front at the left; rear)', fill=(255, 255, 255))
    return im


COLORS = {'mud': (160, 100, 50), 'grime': (110, 110, 120), 'dust': (230, 200, 130), 'bugs': (120, 220, 90), 'snow': (240, 245, 255), 'rubber': (255, 80, 80)}
for kind, color in COLORS.items():
    pts = samples(kind, N)
    p3 = [p for p in (place(u, v) for u, v in pts) if p]
    texture_image(pts, color, kind + ' (the body map rules)').save(os.path.join(out, 'texture_%s.png' % kind))
    views_image(p3, color, kind + ' (the body map rules)').save(os.path.join(out, 'views_%s.png' % kind))
    print(kind, len(pts), 'splats,', len(p3), 'placed')

old = samples('mud', N)
new = traced(N)
a = views_image([p for p in (place(u, v) for u, v in old) if p], (160, 100, 50), 'mud: the wheel-distance rule (old)')
b = views_image([p for p in (place(u, v) for u, v in new) if p], (255, 190, 60), 'mud: traced from the tread (new)')
sheet = Image.new('RGB', (a.width, a.height * 2 + 10), (20, 20, 20))
sheet.paste(a, (0, 0))
sheet.paste(b, (0, a.height + 10))
sheet.save(os.path.join(out, 'compare_mud_views.png'))
ta = texture_image(old, (160, 100, 50), 'mud: wheel-distance rule (old)')
tb = texture_image(new, (255, 190, 60), 'mud: traced spray (new)')
tex = Image.new('RGB', (TEX * 2 + 10, TEX), (20, 20, 20))
tex.paste(ta, (0, 0))
tex.paste(tb, (TEX + 10, 0))
tex.save(os.path.join(out, 'compare_mud_texture.png'))
print('done')
