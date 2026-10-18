// Runs tests/luatest.lua - the rules in mod/lua/ge/extensions/carSurfaceFx - outside the game.
//   npm i fengari   (once, anywhere above this folder or globally)
//   node tools/luatest.js
// fengari is Lua 5.3; the rules are written to run the same there and in the game's LuaJIT.
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const root = path.join(__dirname, '..');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const lp = (p) => JSON.stringify(path.join(root, p).replace(/\\/g, '/'));
const setup = `package.path = ${lp('mod/lua/ge/extensions/?.lua')} .. ';' .. ${lp('mod/lua/common/?.lua')} .. ';' .. package.path`;
if (lauxlib.luaL_dostring(L, to_luastring(setup)) !== lua.LUA_OK) throw new Error('setup failed');
for (const t of ['luatest.lua', 'smoke.lua', 'scratchmem.lua', 'screen_test.lua', 'wheels_test.lua', 'decalprobe_test.lua', 'markswatches_test.lua', 'marks_test.lua', 'fluids_test.lua', 'impacts_test.lua', 'surfaces_test.lua', 'texlist_test.lua', 'ruts_test.lua', 'shim_test.lua', 'debugtools_test.lua', 'grass_test.lua', 'grassprobe_test.lua', 'wear_test.lua', 'glassflow_test.lua']) {
  process.chdir(root);
  const status = lauxlib.luaL_dofile(L, to_luastring(path.join('tests', t)));
  if (status !== lua.LUA_OK) {
    console.error(t + ': ' + to_jsstring(lua.lua_tostring(L, -1)));
    process.exit(1);
  }
}
