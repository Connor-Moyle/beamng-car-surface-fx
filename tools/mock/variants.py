"""Makes variants of the cockpit overlay's drop sprite (and streak colour) from the built csfxRain.js, for mock-ups: python tools/mock/variants.py <csfxRain.js> <out dir>
A is the file as it is; B and C change only the sprite generator and the streak style. Used by tools/mock/make_mockups.sh."""
import os
import re
import sys

src = open(sys.argv[1], encoding='utf8').read()
out = sys.argv[2]
os.makedirs(out, exist_ok=True)

START = "    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {\n      var u = (x + 0.5) / S * 2 - 1"
END = "    c.putImageData(data, 0, 0);"
i = src.index(START)
j = src.index(END, i)

def sprite(lens, ring_a, body_a, streak):
    # layers composited over each other (premultiplied), from the bottom: the dark body (darker in the top half when lens is on: the drop shows the darker ground there), a soft
    # light spot low right, the dark ring all round, a bright rim up-left, the glint
    return """    function over(dst, r, g, b, a) { if (a <= 0) return; var k = 1 - a; dst[0] = r * a + dst[0] * k; dst[1] = g * a + dst[1] * k; dst[2] = b * a + dst[2] * k; dst[3] = a + dst[3] * k; }
    for (var y = 0; y < S; y++) for (var x = 0; x < S; x++) {
      var u = (x + 0.5) / S * 2 - 1, v = (y + 0.5) / S * 2 - 1, d2 = u * u + v * v, o = (y * S + x) * 4;
      if (d2 >= 1) { data.data[o + 3] = 0; continue; }
      var d = Math.sqrt(d2), fade = Math.min(1, (1 - d) * 8), dir = (u + v) * 0.7071, px = [0, 0, 0, 0];
      var top = Math.max(0, -v), body = %(body)s + (%(lens)s ? 0.20 * Math.pow(top, 1.3) : 0);
      over(px, 12, 18, 30, body * (d < 0.9 ? 1 : 0.5));                                          // the body: a dark film, darker toward the top
      var cx = u - 0.22, cy = v - 0.4;
      over(px, 255, 255, 255, 0.30 * Math.exp(-(cx * cx + cy * cy) / 0.10) * (d < 0.9 ? 1 : 0));   // light that the drop focuses, low right
      var ring = Math.max(0, 1 - Math.abs(d - 0.86) / 0.14);
      over(px, 10, 14, 24, Math.min(0.9, ring * %(ring)s * (0.75 + 0.25 * Math.max(0, dir))));      // the dark edge all round, heavier low right
      var rim = ring * Math.max(0, -dir);
      over(px, 255, 255, 255, Math.min(1, rim * 0.95));                                           // the bright rim up-left
      var gx = u + 0.4, gy = v + 0.45;
      over(px, 255, 255, 255, Math.min(1, 1.0 * Math.exp(-(gx * gx + gy * gy) / 0.012)));       // the glint
      var a = px[3];
      data.data[o] = a > 0 ? Math.round(px[0] / a) : 0; data.data[o + 1] = a > 0 ? Math.round(px[1] / a) : 0; data.data[o + 2] = a > 0 ? Math.round(px[2] / a) : 0;
      data.data[o + 3] = Math.min(255, a * fade * 255);
    }
""" % dict(lens='true' if lens else 'false', ring=ring_a, body=body_a)

variants = {
    'A': src,
    'B': src[:i] + sprite(False, 0.75, 0.10, None) + src[j:],
    'C': src[:i] + sprite(True, 0.85, 0.10, None) + src[j:],
}
# streaks: darker and straighter instead of white and wobbly
for k in ('B', 'C'):
    v = variants[k]
    v = v.replace("tctx.strokeStyle = 'rgba(215,230,245,0.34)';", "tctx.strokeStyle = 'rgba(30,40,55,0.20)';")
    v = v.replace("wob = Math.sin(Y * 0.12 + k * 1.7) * w * 0.9", "wob = Math.sin(Y * 0.12 + k * 1.7) * w * 0.25")
    v = v.replace("tctx.moveTo(px[k] + Math.sin(py[k] * 0.12 + k * 1.7) * w * 0.9, py[k])", "tctx.moveTo(px[k] + Math.sin(py[k] * 0.12 + k * 1.7) * w * 0.25, py[k])")
    variants[k] = v
for k, text in variants.items():
    open(os.path.join(out, 'overlay_%s.js' % k), 'w', encoding='utf8').write(text)
print('variants', ', '.join(sorted(variants)))
