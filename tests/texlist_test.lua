-- P13: the pictures a player can drop into a folder (carSurfaceFx/texlist.lua).
local T = require('carSurfaceFx/texlist')
local list = { 'puddle_1.png', 'puddle_2.png', 'puddle_mine.PNG' }

assert(T.pick(list, '', 0) == 'puddle_1.png' and T.pick(list, '', 0.5) == 'puddle_2.png' and T.pick(list, '', 0.99) == 'puddle_mine.PNG', 'any: by seed')
assert(T.pick(list, 'puddle_2.png', 0.9) == 'puddle_2.png' and T.pick(list, '/art/decals/fluids/puddle_2.png', 0.9) == 'puddle_2.png', 'a chosen file, with or without its folder')
assert(T.pick(list, 'PUDDLE_MINE.png', 0) == 'puddle_mine.PNG', 'case-insensitive')
assert(T.pick(list, 'gone.png', 0) == 'puddle_1.png', 'a choice that is not there falls back to any')
assert(T.pick({}, '', 0) == nil and T.pick(nil, '', 0) == nil, 'nothing to pick')
assert(#T.shown(list, '') == 3 and #T.shown(list, 'puddle_1.png') == 1 and T.shown(list, 'puddle_1.png')[1] == 'puddle_1.png' and #T.shown(list, 'gone.png') == 3, 'what a draw loop walks')
assert(T.indexFor(3, 0) == 1 and T.indexFor(3, 0.5) == 2 and T.indexFor(3, 0.99) == 3 and T.indexFor(0, 0.5) == 0 and T.indexFor(1, 0.7) == 1, 'a seed picks a slot')

local saved = rawget(_G, 'FS')
FS = { findFiles = function(_, dir, pattern) assert(dir == '/art/decals/fluids/' and pattern == '*.png') return { '/art/decals/fluids/puddle_b.png', '/art/decals/fluids/puddle_a.png', '/art/decals/fluids/other.png', '/art/decals/fluids/Puddle_C.png' } end }
local found = T.scan('art/decals/fluids/', 'puddle')
assert(#found == 3 and found[1] == 'Puddle_C.png' and found[2] == 'puddle_a.png' and found[3] == 'puddle_b.png', 'the folder: the right prefix, sorted: ' .. table.concat(found, ','))
FS = nil
assert(#T.scan('art/decals/fluids/', 'puddle') == 0, 'without the file system nothing is found (the modules use the pictures that ship)')
FS = saved
print('carSurfaceFx texlist: ok')
