"""Makes mod/art/surfacefx/marks/berm.materials.json: one opaque soil material per rut ground (csfx_berm_<kind>) from the rut textures (colour, normal, roughness, ao), no opacity map.
Run: python tools/make_berm_materials.py   (check: it rewrites the file the same way every time)"""
import json, os, uuid

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'mod', 'art', 'surfacefx', 'marks')
KINDS = ['mud', 'snow', 'sand', 'dirt', 'gravel']
src = json.load(open(os.path.join(ROOT, 'main.materials.json')))
out = {}
for kind in KINDS:
    stage = dict(src['csfx_rut_%s_dry' % kind]['Stages'][0])
    stage.pop('opacityMap', None)
    stage.pop('opacityFactor', None)
    stage['baseColorFactor'] = [0.85, 0.85, 0.85, 1]
    name = 'csfx_berm_' + kind
    out[name] = {
        'name': name, 'mapTo': name, 'class': 'Material', 'persistentId': str(uuid.uuid5(uuid.NAMESPACE_DNS, name)),
        'Stages': [stage, {}, {}, {}], 'annotation': 'NATURE', 'materialTag0': 'RoadAndPath', 'translucent': False, 'version': 1.5,
    }
with open(os.path.join(ROOT, 'berm.materials.json'), 'w', newline='\n') as f:
    json.dump(out, f, indent=2)
    f.write('\n')
print('wrote', len(out), 'berm materials')
