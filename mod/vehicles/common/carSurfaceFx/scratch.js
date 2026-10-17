// Car Surface FX - scratch and splat paint canvas (from Enhanced Skid Marks). Runs inside a per-vehicle web texture; every vehicle that
// gets marks has TWO of these pages, told apart by the ?m= in the URL:
//   ?m=b  the paint layer's BASE COLOUR map. starts white; marks are drawn in their real colour.
//   ?m=p  the paint layer's COLOUR PALETTE map. starts solid red (= "paint colour 1 everywhere");
//         marks are ERASED from it, because the shader shows the base colour un-tinted wherever
//         the palette's alpha is gone.
// GE lua (carSurfaceFx/scratch.lua) works out every position and size and sends the SAME call to
// both pages, so the two always line up. Coordinates are 0..1 across the canvas.

(function () {
  var canvas = document.getElementById('csfxScratchCanvas');
  var ctx = canvas.getContext('2d');
  var palette = /[?&]m=p/.test(location.search);
  var dark = /[?&]dark=1/.test(location.search);   // this car has no palette to punch through: marks can only darken
  var W = canvas.width = canvas.height = 1024;

  // the engine reads this texture as LINEAR colour, so a plain sRGB value comes out washed-out: pre-darken it
  function ch(x) { return Math.round(Math.pow(Math.max(0, Math.min(1, x)), 2.2) * 255); }
  function rgba(c, a) { return 'rgba(' + ch(c[0]) + ',' + ch(c[1]) + ',' + ch(c[2]) + ',' + a + ')'; }
  // base page: paint in colour c. palette page: punch the same shape out instead.
  // the base goes on much heavier than the punch-out: what shows is base x (white..paint by what's left of
  // the palette), so any white left in the base under a part-erased palette reads as chalky, not as the colour.
  function ink(c, a) {
    if (!palette) a = 1 - Math.pow(1 - a, 4);
    ctx.globalCompositeOperation = palette ? 'destination-out' : 'source-over';
    ctx.strokeStyle = ctx.fillStyle = palette ? 'rgba(0,0,0,' + a + ')' : rgba(c, a);
  }

  window.csfxClear = function () {
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = palette ? '#f00' : '#fff';
    ctx.fillRect(0, 0, W, W);
  };

  // o = { l: [x1,y1,x2,y2,width, ...], c: [r,g,b], a }. each scratch is a dark soft edge with the
  // real colour down the middle, so it reads on light AND dark paint.
  window.csfxLines = function (o) {
    ctx.lineCap = 'round';
    for (var pass = 0; pass < 2; pass++) {
      var edge = pass === 0;
      var k = dark ? 0.12 : (edge ? 0.3 : 1);
      ink([o.c[0] * k, o.c[1] * k, o.c[2] * k], edge ? o.a * 0.5 : o.a);
      for (var i = 0; i < o.l.length; i += 5) {
        ctx.lineWidth = Math.max(1, o.l[i + 4] * W) + (edge ? 1.5 : 0);
        ctx.beginPath();
        ctx.moveTo(o.l[i] * W, o.l[i + 1] * W);
        ctx.lineTo(o.l[i + 2] * W, o.l[i + 3] * W);
        ctx.stroke();
      }
    }
  };

  // o = { l: [x,y,radius, ...], c: [r,g,b], a } - soft-edged dirt splats. base page ONLY: dirt just
  // darkens/tints the paint. punching the palette too exposes the bare layer, which is as shiny as metal -
  // right for a scratch, but it made dirt look like chrome with a dark rim.
  window.csfxBlobs = function (o) {
    if (palette) return;
    ctx.globalCompositeOperation = 'source-over';
    var solid = rgba(o.c, o.a), clear = rgba(o.c, 0);
    for (var i = 0; i < o.l.length; i += 3) {
      var x = o.l[i] * W, y = o.l[i + 1] * W, r = Math.max(2, o.l[i + 2] * W);
      var g = ctx.createRadialGradient(x, y, r * 0.2, x, y, r);
      g.addColorStop(0, solid); g.addColorStop(1, clear);
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
    }
  };

  window.csfxClear();
})();
