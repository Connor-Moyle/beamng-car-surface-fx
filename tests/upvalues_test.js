// the mod's Lua must stay under LuaJIT's 60-upvalue limit per function (tools/upvalues.js); a load failure in the game otherwise
const { execFileSync } = require('child_process');
const path = require('path');
console.log(execFileSync(process.execPath, [path.join(__dirname, '..', 'tools', 'upvalues.js')], { encoding: 'utf8' }).trim());
