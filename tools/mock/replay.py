"""Draws a recording of the cockpit overlay (tools/mock/record.js) over a backdrop picture and writes a PNG: a mock-up of what the game's web UI layer shows over the 3D scene.
It replays the canvas calls the overlay makes (source-over and destination-out, clips, scaled drawImage, simple paths and strokes) with numpy and PIL: close to a browser's
canvas, not identical (no anti-aliasing on paths), good enough to compare looks.

    python tools/mock/replay.py <rec.json> <backdrop image> <out.png> [crop x0 y0 x1 y1 (fractions)] [zoom]
"""
import base64
import json
import re
import sys

import numpy as np
from PIL import Image, ImageDraw


def color(text):
    t = str(text).strip()
    m = re.match(r'rgba?\(([^)]*)\)', t)
    if m:
        p = [float(x) for x in m.group(1).split(',')]
        return (p[0] / 255, p[1] / 255, p[2] / 255, p[3] if len(p) > 3 else 1.0)
    if t.startswith('#'):
        h = t[1:]
        if len(h) == 3:
            h = ''.join(c * 2 for c in h)
        return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, 1.0)
    return (0, 0, 0, 1.0)


class Cv:
    def __init__(self):
        self.dim(300, 150)
        self.state = dict(fill=(0, 0, 0, 1.0), stroke=(0, 0, 0, 1.0), lw=1.0, cap='butt', ga=1.0, comp='source-over')
        self.stack = []
        self.path = []
        self.cur = None
        self.clip = None

    def dim(self, w, h):
        self.w, self.h = int(w), int(h)
        self.a = np.zeros((self.h, self.w, 4), np.float32)          # premultiplied RGBA

    # ---- compositing of a premultiplied source (h, w, 4) at integer x, y
    def put(self, src, x, y, mask=None, comp=None, ga=None):
        comp = comp or self.state['comp']
        ga = self.state['ga'] if ga is None else ga
        sh, sw = src.shape[:2]
        x0, y0, x1, y1 = max(0, x), max(0, y), min(self.w, x + sw), min(self.h, y + sh)
        if x1 <= x0 or y1 <= y0:
            return
        s = src[y0 - y:y1 - y, x0 - x:x1 - x]
        m = np.full(s.shape[:2], ga, np.float32)
        if mask is not None:
            m = m * mask[y0 - y:y1 - y, x0 - x:x1 - x]
        if self.clip is not None:
            m = m * self.clip[y0:y1, x0:x1]
        d = self.a[y0:y1, x0:x1]
        if comp == 'destination-out':
            d *= (1 - s[..., 3:4] * m[..., None])
        elif comp == 'multiply':
            sa = s[..., 3:4] * m[..., None]
            d[:] = d * (1 - sa) + s * m[..., None] * (1 - d[..., 3:4]) + d * s * m[..., None]
        else:
            d[:] = s * m[..., None] + d * (1 - s[..., 3:4] * m[..., None])

    def flat(self, rgba):
        r, g, b, a = rgba
        return np.array([r * a, g * a, b * a, a], np.float32)

    def fill_rect(self, x, y, w, h):
        x0, y0 = int(round(x)), int(round(y))
        w, h = int(round(w)), int(round(h))
        if w <= 0 or h <= 0:
            return
        src = np.empty((h, w, 4), np.float32)
        src[:] = self.flat(self.state['fill'])
        self.put(src, x0, y0)

    def clear_rect(self, x, y, w, h):
        x0, y0 = max(0, int(x)), max(0, int(y))
        x1, y1 = min(self.w, int(x + w + 0.999)), min(self.h, int(y + h + 0.999))
        if x1 <= x0 or y1 <= y0:
            return
        if self.clip is None:
            self.a[y0:y1, x0:x1] = 0
        else:
            self.a[y0:y1, x0:x1] *= (1 - self.clip[y0:y1, x0:x1])[..., None]

    def draw_image(self, src, args):
        if len(args) == 2:
            sx, sy, sw, sh, dx, dy, dw, dh = 0, 0, src.w, src.h, args[0], args[1], src.w, src.h
        elif len(args) == 4:
            sx, sy, sw, sh, dx, dy, dw, dh = 0, 0, src.w, src.h, *args
        else:
            sx, sy, sw, sh, dx, dy, dw, dh = args
        sx, sy, sw, sh = int(sx), int(sy), int(sw), int(sh)
        part = src.a[sy:sy + sh, sx:sx + sw]
        if part.size == 0 or dw <= 0.2 or dh <= 0.2:
            return
        w2, h2 = max(1, int(round(dw))), max(1, int(round(dh)))
        if (w2, h2) != (part.shape[1], part.shape[0]):
            chans = [np.asarray(Image.fromarray(np.ascontiguousarray(part[..., c]), mode='F').resize((w2, h2), Image.BILINEAR)) for c in range(4)]
            part = np.stack(chans, -1)
        self.put(part, int(round(dx)), int(round(dy)))

    # ---- paths
    def begin(self):
        self.path, self.cur = [], None

    def move(self, x, y):
        self.cur = [(x, y)]
        self.path.append(self.cur)

    def line(self, x, y):
        if self.cur is None:
            self.move(x, y)
        else:
            self.cur.append((x, y))

    def arc(self, x, y, r, a0, a1, ccw=False):
        n = max(8, int(abs(a1 - a0) * max(r, 1) ** 0.5 * 2))
        pts = [(x + r * np.cos(a0 + (a1 - a0) * i / n), y + r * np.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
        if self.cur is None:
            self.cur = pts
            self.path.append(self.cur)
        else:
            self.cur.extend(pts)

    def raster(self, polys, stroke=False):
        pts = [p for sub in polys for p in sub]
        if not pts:
            return None
        pad = int(self.state['lw'] / 2 + 3) if stroke else 2
        x0, y0 = max(0, int(min(p[0] for p in pts)) - pad), max(0, int(min(p[1] for p in pts)) - pad)
        x1, y1 = min(self.w, int(max(p[0] for p in pts)) + pad + 1), min(self.h, int(max(p[1] for p in pts)) + pad + 1)
        if x1 <= x0 or y1 <= y0:
            return None
        im = Image.new('L', (x1 - x0, y1 - y0), 0)
        dr = ImageDraw.Draw(im)
        for sub in polys:
            loc = [(p[0] - x0, p[1] - y0) for p in sub]
            if stroke:
                w = max(1, int(round(self.state['lw'])))
                dr.line(loc, fill=255, width=w, joint='curve')
                if self.state['cap'] == 'round' and w > 2:
                    for q in (loc[0], loc[-1]):
                        dr.ellipse([q[0] - w / 2, q[1] - w / 2, q[0] + w / 2, q[1] + w / 2], fill=255)
            elif len(loc) >= 3:
                dr.polygon(loc, fill=255)
        return x0, y0, np.asarray(im, np.float32) / 255

    def paint(self, stroke):
        r = self.raster(self.path, stroke)
        if r is None:
            return
        x0, y0, m = r
        col = self.state['stroke' if stroke else 'fill']
        src = np.empty(m.shape + (4,), np.float32)
        src[:] = self.flat(col)
        self.put(src, x0, y0, mask=m)

    def do_clip(self):
        im = Image.new('L', (self.w, self.h), 0)
        dr = ImageDraw.Draw(im)
        for sub in self.path:
            if len(sub) >= 3:
                dr.polygon(sub, fill=255)
        m = np.asarray(im, np.float32) / 255
        self.clip = m if self.clip is None else self.clip * m

    def save(self):
        self.stack.append((dict(self.state), self.clip))

    def restore(self):
        if self.stack:
            self.state, self.clip = self.stack.pop()


def replay(rec, upto=None):
    cvs = {}
    for op in rec['ops']:
        cid, name, args = op[0], op[1], op[2:]
        if cid < 0:
            continue
        c = cvs.setdefault(cid, Cv())
        if name == 'dim':
            c.dim(*args)
        elif name == 'set':
            k, v = args
            s = c.state
            if k == 'fillStyle': s['fill'] = color(v)
            elif k == 'strokeStyle': s['stroke'] = color(v)
            elif k == 'lineWidth': s['lw'] = float(v)
            elif k == 'lineCap': s['cap'] = v
            elif k == 'globalAlpha': s['ga'] = float(v)
            elif k == 'globalCompositeOperation': s['comp'] = v
        elif name == 'putImageData':
            data, w, h, x, y = args[0], args[1], args[2], args[3], args[4]
            px = np.frombuffer(base64.b64decode(data), np.uint8).reshape(h, w, 4).astype(np.float32) / 255
            pre = px.copy()
            pre[..., :3] *= px[..., 3:4]
            c.a[y:y + h, x:x + w] = pre
        elif name == 'save': c.save()
        elif name == 'restore': c.restore()
        elif name == 'beginPath': c.begin()
        elif name == 'moveTo': c.move(*args)
        elif name == 'lineTo': c.line(*args)
        elif name == 'closePath': pass
        elif name == 'arc': c.arc(*args)
        elif name == 'clip': c.do_clip()
        elif name == 'fill': c.paint(False)
        elif name == 'stroke': c.paint(True)
        elif name == 'fillRect': c.fill_rect(*args)
        elif name == 'clearRect': c.clear_rect(*args)
        elif name == 'drawImage': c.draw_image(cvs[args[0]], args[1:])
    return cvs


def main():
    rec = json.load(open(sys.argv[1]))
    back = Image.open(sys.argv[2]).convert('RGB')
    W, H = rec['W'], rec['H']
    back = back.resize((W, H), Image.LANCZOS)
    cvs = replay(rec)
    ov = cvs[rec['canvas']].a
    bg = np.asarray(back, np.float32) / 255
    h, w = min(H, ov.shape[0]), min(W, ov.shape[1])
    out = bg.copy()
    out[:h, :w] = ov[:h, :w, :3] + bg[:h, :w] * (1 - ov[:h, :w, 3:4])
    img = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))
    if len(sys.argv) > 7:
        x0, y0, x1, y1 = [float(v) for v in sys.argv[4:8]]
        img = img.crop((int(x0 * W), int(y0 * H), int(x1 * W), int(y1 * H)))
    zoom = float(sys.argv[8]) if len(sys.argv) > 8 else 1.0
    if zoom != 1.0:
        img = img.resize((int(img.width * zoom), int(img.height * zoom)), Image.LANCZOS)
    img.save(sys.argv[3])
    print('wrote', sys.argv[3], img.size)


if __name__ == '__main__':
    main()
