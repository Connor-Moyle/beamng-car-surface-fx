-- P12: the map makers' surface names (carSurfaceFx/surfaces.lua).
local S = require('carSurfaceFx/surfaces')

assert(S.guess('GRASS_LONG') == 'grass' and S.guess('red_Sand_beach') == 'sand' and S.guess('Snow_deep') == 'snow' and S.guess('muddy_dirt') == 'mud', 'guess by name, mud before dirt')
assert(S.guess('ice_sheet') == 'ice' and S.guess('Gravel_Pit') == 'gravel' and S.guess('forest_trail') == 'dirt' and S.guess('concrete') == nil, 'known and unknown names')

-- the old Surface FX file format, exactly
local old = { mapName = 'EXAMPLE_map', materials = { dirt = { 'dust', 'DryEarth' }, sand = { 'redsand', 'beach' }, mud = { 'wetmud', 'bog' }, lava = { 'magma' } } }
assert(S.fromFile(old, '/levels/other/main.level.json') == nil, 'a file for another map is ignored')
local mine = S.fromFile(old, '/levels/example_map/info.json')
assert(mine and mine.dust == 'dirt' and mine.dryearth == 'dirt' and mine.redsand == 'sand' and mine.bog == 'mud' and mine.magma == nil, 'case-insensitive names, unknown kinds dropped')
for _, m in ipairs({ '*', 'all', '' }) do
  assert(S.fromFile({ mapName = m, materials = { grass = { 'meadow' } } }, '/levels/anything/x.json').meadow == 'grass', 'mapName "' .. m .. '" is every map')
end
assert(S.fromFile({ materials = { grass = { 'meadow' } } }, 'x').meadow == 'grass', 'no mapName is every map')
assert(S.fromFile({ mapName = '*' }, 'x') == nil and S.fromFile('nope', 'x') == nil, 'a file without materials is nothing')
local merged = S.merge({ { mapName = '*', materials = { dirt = { 'a' }, sand = { 'b' } } }, { mapName = '*', materials = { mud = { 'a' } } } }, 'x')
assert(merged.a == 'mud' and merged.b == 'sand', 'a later file wins')

-- names turned into collision type ids: a ground model of the level, or a game material by name
local gms = { SANDY_BEACH = { cdata = { collisiontype = 41 } }, ROAD_ASPHALT = { cdata = { collisiontype = 10 } }, FOREST_MUD_X = { cdata = { collisiontype = 43 } }, ODD_THING = { cdata = { collisiontype = 44 } } }
local mats = { [10] = { name = 'ASPHALT' }, [15] = { name = 'DIRT' }, [20] = { name = 'GRASS' } }
local known = { [10] = true, [15] = true, [20] = true }
local ids, notes = S.resolve({ dirt = nil, dust = 'dirt', odd_thing = 'gravel', grass = 'grass', nowhere = 'ice' }, gms, mats, known)
assert(ids[44] == 'gravel' and ids[20] == 'grass' and ids[41] == 'sand' and ids[43] == 'mud', 'explicit entries by ground model and by material name, the rest guessed: ' .. S.literal(ids))
assert(ids[10] == nil, 'ids the car knows by name are left alone')
local why = table.concat(notes, ';')
assert(why:find('dust is no ground model') and why:find('nowhere is no ground model'), 'a name that matches nothing is said: ' .. why)
local ids2 = S.resolve({ odd_thing = 'ice' }, gms, mats, known)
assert(ids2[44] == 'ice', 'an explicit entry beats the guess')
assert(S.literal({ [43] = 'mud', [41] = 'sand' }) == '{[41]="sand",[43]="mud"}' and S.literal({}) == '{}', 'the literal for the car')

-- the game side with files
local files = {
  ['/carSurfaceFx/a.json'] = { mapName = '*', materials = { snow = { 'odd_thing' } } },
  ['/dirtSkidMarks/b.json'] = { mapName = 'my_level', materials = { mud = { 'forest_mud_x' } } },
  ['/dirtSkidMarks/c.json'] = { mapName = 'elsewhere', materials = { ice = { 'sandy_beach' } } },
}
local saved = { FS = rawget(_G, 'FS'), jsonReadFile = jsonReadFile, getMissionFilename = getMissionFilename, core_environment = core_environment, particles = package.loaded['particles'] }
FS = { findFiles = function(_, folder) local out = {} for f in pairs(files) do if f:sub(1, #folder) == folder then out[#out + 1] = f end end return out end }
jsonReadFile = function(f) return files[f] end
getMissionFilename = function() return '/levels/my_level/main.level.json' end
core_environment = { groundModels = gms }
package.loaded['particles'] = { getMaterialsParticlesTable = function() return mats end }
local lit = S.rescan()
assert(lit[44] == 'snow' and lit[43] == 'mud' and lit[41] == 'sand', 'both folders are read, files for other maps are not: ' .. S.literal(lit))
assert(S.literalNow() == '{[41]="sand",[43]="mud",[44]="snow"}', 'the literal of the level')
getMissionFilename = function() return '/levels/elsewhere/x.json' end
assert(S.rescan()[41] == 'ice', 'another level, another file')

FS, jsonReadFile, getMissionFilename, core_environment, package.loaded['particles'] = saved.FS, saved.jsonReadFile, saved.getMissionFilename, saved.core_environment, saved.particles
print('carSurfaceFx surfaces: ok')
