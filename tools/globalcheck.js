// Finds undefined globals (a call to a function that is not defined, a typo) in the mod's Lua files, with scoping, so a mistake like a deleted local helper
// fails here and not every frame in the game.   npm i luaparse (once, anywhere above or globally);   node tools/globalcheck.js
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const STD = 'assert error ipairs pairs next pcall xpcall select setmetatable getmetatable rawget rawset rawequal tonumber tostring type unpack require print math string table os io _G coroutine'.split(' ');
const GAME = {
  ge: 'ColorF castRayStatic debugDrawer be log scenetree createObject Sim jsonReadFile jsonWriteFile deepcopy core_environment core_vehicle_manager core_camera extensions sl_weather surfaceFXBody Engine jsonEncode UI_TEXTURE_USAGE_AUTOMATIC setExtensionUnloadMode carSurfaceFx_scratch carSurfaceFx_meshuv surfaceFXHiFiScratch getAllVehicles getObjectByID tableKeys tableSize hptimer readFile FS getPlayerVehicle dumps unpack vec3 ui_options guihooks quat getCurrentLevelIdentifier core_terrain util_surfaceMaskWheels carSurfaceFx_grass carSurfaceFx_marks carSurfaceFx_fluids slrr_settings'.split(' '),
  vehicle: 'obj electrics wheels log extensions carSurfaceFxWheels v onNodeCollision damageTracker powertrain energyStorage particles carSurfaceFxContact'.split(' '),
};
const root = process.argv[2] || path.join(__dirname, '..', 'mod', 'lua');
const files = [];
(function walk(d) { for (const f of fs.readdirSync(d, { withFileTypes: true })) f.isDirectory() ? walk(path.join(d, f.name)) : f.name.endsWith('.lua') && files.push(path.join(d, f.name)); })(root);

let bad = 0;
for (const file of files) {
  const allowed = new Set([...STD, ...(file.includes(path.sep + 'vehicle' + path.sep) ? GAME.vehicle : GAME.ge)]);
  const ast = luaparse.parse(fs.readFileSync(file, 'utf8'), { luaVersion: '5.3', locations: true });
  const scopes = [new Set()];
  const declared = (n) => scopes.some((s) => s.has(n));
  function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(walk); return; }
    switch (node.type) {
      case 'LocalStatement':
        node.init.forEach(walk);                                  // the initialisers cannot see the new locals
        node.variables.forEach((v) => scopes[scopes.length - 1].add(v.name));
        return;
      case 'FunctionDeclaration': {
        if (node.identifier && node.identifier.type === 'Identifier') {
          if (node.isLocal) scopes[scopes.length - 1].add(node.identifier.name); else walk(node.identifier);
        } else if (node.identifier) walk(node.identifier);
        scopes.push(new Set(node.parameters.filter((p) => p.type === 'Identifier').map((p) => p.name)));
        walk(node.body);
        scopes.pop();
        return;
      }
      case 'ForNumericStatement':
        walk(node.start); walk(node.end); walk(node.step);
        scopes.push(new Set([node.variable.name])); walk(node.body); scopes.pop();
        return;
      case 'ForGenericStatement':
        walk(node.iterators);
        scopes.push(new Set(node.variables.map((v) => v.name))); walk(node.body); scopes.pop();
        return;
      case 'DoStatement': case 'WhileStatement': case 'RepeatStatement': case 'IfClause': case 'ElseifClause': case 'ElseClause':
        scopes.push(new Set()); for (const k of Object.keys(node)) if (k !== 'type' && k !== 'loc' && k !== 'range') walk(node[k]); scopes.pop();
        return;
      case 'TableKeyString': walk(node.value); return;             // { name = value }: name is a key
      case 'MemberExpression': walk(node.base); return;           // .name is a field, not a variable
      case 'Identifier':
        if (!declared(node.name) && !allowed.has(node.name)) {
          console.log(`${path.relative(root, file)}:${node.loc.start.line}: undefined global '${node.name}'`);
          bad++;
        }
        return;
    }
    for (const k of Object.keys(node)) if (k !== 'type' && k !== 'loc' && k !== 'range') walk(node[k]);
  }
  walk(ast.body);
}
console.log(bad ? `${bad} undefined global(s)` : `no undefined globals in ${files.length} files`);
process.exit(bad ? 1 : 0);
