// LuaJIT refuses to load a function that uses more than 60 outer locals ("function at line N has more than 60 upvalues"); a normal Lua test does not notice.
// Counts the upvalues of every function in the mod's Lua files and fails above 60.   node tools/upvalues.js [root]   (needs luaparse)
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const LIMIT = 60;
const root = process.argv[2] || path.join(__dirname, '..', 'mod', 'lua');
const files = [];
(function walk(d) { for (const f of fs.readdirSync(d, { withFileTypes: true })) f.isDirectory() ? walk(path.join(d, f.name)) : f.name.endsWith('.lua') && files.push(path.join(d, f.name)); })(root);

let bad = 0, worst = { n: 0 };
for (const file of files) {
  const ast = luaparse.parse(fs.readFileSync(file, 'utf8'), { luaVersion: 'LuaJIT', locations: true });
  const fns = [{ upv: new Set(), line: 0 }];                      // the chunk itself
  const scopes = [{ names: new Map(), fn: 0 }];                   // name -> unique id of that local
  let uid = 0;
  const add = (n) => scopes[scopes.length - 1].names.set(n, ++uid);
  function use(name) {
    for (let i = scopes.length - 1; i >= 0; i--) {
      const id = scopes[i].names.get(name);
      if (id === undefined) continue;
      for (let f = scopes[i].fn + 1; f < fns.length; f++) fns[f].upv.add(id);   // every function between the owner and here carries it
      return;
    }
  }
  const push = (names) => { scopes.push({ names: new Map(), fn: fns.length - 1 }); (names || []).forEach(add); };
  function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(walk); return; }
    switch (node.type) {
      case 'LocalStatement':
        node.init.forEach(walk);
        node.variables.forEach((v) => add(v.name));
        return;
      case 'FunctionDeclaration': {
        if (node.identifier && node.identifier.type === 'Identifier') {
          if (node.isLocal) add(node.identifier.name); else use(node.identifier.name);
        } else if (node.identifier) walk(node.identifier);
        const f = { upv: new Set(), line: node.loc.start.line, file };
        fns.push(f);
        push(node.parameters.filter((p) => p.type === 'Identifier').map((p) => p.name));
        walk(node.body);
        scopes.pop();
        fns.pop();
        if (f.upv.size > worst.n) worst = { n: f.upv.size, file: path.relative(root, file), line: f.line };
        if (f.upv.size > LIMIT) { console.log(`${path.relative(root, file)}:${f.line}: function has ${f.upv.size} upvalues (limit ${LIMIT})`); bad++; }
        return;
      }
      case 'ForNumericStatement': walk(node.start); walk(node.end); walk(node.step); push([node.variable.name]); walk(node.body); scopes.pop(); return;
      case 'ForGenericStatement': walk(node.iterators); push(node.variables.map((v) => v.name)); walk(node.body); scopes.pop(); return;
      case 'DoStatement': case 'WhileStatement': case 'RepeatStatement': case 'IfClause': case 'ElseifClause': case 'ElseClause':
        push(); for (const k of Object.keys(node)) if (k !== 'type' && k !== 'loc' && k !== 'range') walk(node[k]); scopes.pop();
        return;
      case 'TableKeyString': walk(node.value); return;
      case 'MemberExpression': walk(node.base); return;
      case 'Identifier': use(node.name); return;
    }
    for (const k of Object.keys(node)) if (k !== 'type' && k !== 'loc' && k !== 'range') walk(node[k]);
  }
  walk(ast.body);
}
console.log(bad ? `${bad} function(s) over ${LIMIT} upvalues` : `no function over ${LIMIT} upvalues in ${files.length} files (most: ${worst.n} at ${worst.file}:${worst.line})`);
process.exit(bad ? 1 : 0);
