"""Ships the game's own cooked DDS of the ground-mark textures instead of the PNGs (0.40 cooks a PNG at runtime; the same rule as the tyre overlays, see make_tyre_stage_textures.py).
Run the game with every mark material drawn once (see docs/COOKING_MARKS.md), then:
  python tools/ingest_cooked_dds.py <cooked folder: <user folder>/current/temp/art/surfacefx/marks> [--apply] [--into <mod folder with the PNGs>]
--into: another folder of PNGs (default mod/art/surfacefx/marks), e.g. mod/art/surfacefx/fluids; only PNGs under it are touched.
For each PNG under mod/art/surfacefx/marks/ the cooked <same name>.dds is copied beside it and the PNG removed (the materials keep naming the .png, as the game's own materials name their DDS).
Without --apply it only reports. A PNG with no cooked file is left alone and listed; exit 1 when any is missing."""
import os, shutil, sys

MARKS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'mod', 'art', 'surfacefx', 'marks')


def plan(cooked, marks=MARKS):
    """-> (pairs [(png, dds)], missing [png]); the cooked file is found by its stem anywhere under the cooked folder"""
    found = {}
    for root, _, files in os.walk(cooked):
        for f in files:
            if f.lower().endswith('.dds'):
                found[os.path.splitext(f)[0].lower()] = os.path.join(root, f)
    pairs, missing = [], []
    for root, _, files in os.walk(marks):
        for f in sorted(files):
            if f.lower().endswith('.png'):
                png = os.path.join(root, f)
                dds = found.get(os.path.splitext(f)[0].lower())
                (pairs if dds else missing).append((png, dds) if dds else png)
    return pairs, missing


def apply(pairs):
    for png, dds in pairs:
        shutil.copyfile(dds, os.path.splitext(png)[0] + '.dds')
        os.remove(png)


def selftest():
    import tempfile
    t = tempfile.mkdtemp(); m = os.path.join(t, 'marks'); c = os.path.join(t, 'cooked')
    os.makedirs(os.path.join(m, 'rut_x')); os.makedirs(os.path.join(c, 'rut_x'))
    for n in ('a.png', 'b.png'):
        open(os.path.join(m, 'rut_x', n), 'wb').write(b'png')
    open(os.path.join(c, 'rut_x', 'a.dds'), 'wb').write(b'dds')
    pairs, missing = plan(c, m)
    assert len(pairs) == 1 and len(missing) == 1 and missing[0].endswith('b.png')
    apply(pairs)
    assert os.path.exists(os.path.join(m, 'rut_x', 'a.dds')) and not os.path.exists(os.path.join(m, 'rut_x', 'a.png')) and os.path.exists(os.path.join(m, 'rut_x', 'b.png'))
    print('ingest_cooked_dds selftest ok')


if __name__ == '__main__':
    if '--selftest' in sys.argv:
        selftest()
        sys.exit(0)
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args:
        sys.exit(__doc__)
    into = sys.argv[sys.argv.index('--into') + 1] if '--into' in sys.argv else MARKS
    args = [a for a in args if a != into]
    pairs, missing = plan(args[0], into)
    print('%d to ship as DDS, %d with no cooked file' % (len(pairs), len(missing)))
    for m in missing:
        print('  missing:', os.path.relpath(m, into))
    if '--apply' in sys.argv:
        apply(pairs)
        print('applied')
    sys.exit(1 if missing else 0)
