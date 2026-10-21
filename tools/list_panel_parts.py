"""Lists the body parts of the game's stock vehicles that are not plain painted metal, from the jbeam files themselves (facts, not guesses), to fill the panel material table
(mod/lua/ge/extensions/carSurfaceFx/panelrules.lua PART_KINDS):

    python tools/list_panel_parts.py [game dir]            a summary: per family the part names found, by vehicle
    python tools/list_panel_parts.py [game dir] --all      also every part name that matched no family

A "part" is a top-level key of a vehicle .jbeam (the name a node's partOrigin carries). The families are the words in the table: carbon, fibreglass, plastic trim.
"""
import collections
import glob
import os
import re
import sys
import zipfile

GAME = r"I:\SteamLibrary\steamapps\common\BeamNG.drive"
args = [a for a in sys.argv[1:] if not a.startswith('--')]
game = args[0] if args else GAME
FAMILIES = [
    ('carbon', re.compile(r'carbon', re.I)),
    ('fibreglass', re.compile(r'fiberglass|fibreglass|glassfiber|frp', re.I)),
    ('plastic', re.compile(r'bumper|fascia|grille|mirror|flare|spoiler|splitter|cladding|valance|skirt|diffuser|lip|wing', re.I)),
]
# parts that match a word above but are not a body panel (brakes, internal)
NOT_BODY = re.compile(r'brake|disc|pad|caliper|rotor|wheel|tire|tyre|engine|intake|interior|seat|dash|steer|exhaust|suspension|strut|gauge', re.I)

found = collections.defaultdict(lambda: collections.defaultdict(set))
unmatched = collections.defaultdict(set)
for z in sorted(glob.glob(os.path.join(game, 'content', 'vehicles', '*.zip'))):
    car = os.path.basename(z)[:-4]
    zf = zipfile.ZipFile(z)
    for n in zf.namelist():
        if not n.endswith('.jbeam'):
            continue
        try:
            text = zf.read(n).decode('utf8', 'ignore')
        except Exception:
            continue
        for m in re.finditer(r'^\s*"([A-Za-z0-9_]+)"\s*:\s*\{', text, re.M):
            part = m.group(1)
            if NOT_BODY.search(part):
                continue
            for fam, rx in FAMILIES:
                if rx.search(part):
                    found[fam][car].add(part)
                    break
            else:
                unmatched[car].add(part)

for fam, _ in FAMILIES:
    print('==', fam, '==', sum(len(v) for v in found[fam].values()), 'parts in', len(found[fam]), 'vehicles')
    for car in sorted(found[fam]):
        names = sorted(found[fam][car])
        print('  %-14s %s' % (car, ', '.join(names[:12]) + (' ...(%d)' % len(names) if len(names) > 12 else '')))
if '--all' in sys.argv:
    print('== matched no family ==')
    for car in sorted(unmatched):
        print('  %-14s %d parts' % (car, len(unmatched[car])))
