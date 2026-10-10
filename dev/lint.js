// Minimal luacheck stand-in: Lua 5.1 syntax check + scope-aware global report.
// usage: node lint.js file.lua [more.lua ...]
// Prints: SYNTAX errors, then every global READ or WRITTEN that is not in the
// allowlist (std Lua 5.1 + a short list of WoW globals). Unknown globals are not
// necessarily bugs: check each name against the API dump (grep /tmp/wowui).
const fs = require('fs');
const luaparse = require('luaparse');

const STD = new Set(`_G _VERSION assert collectgarbage error getfenv getmetatable ipairs load loadstring next pairs pcall print rawequal rawget rawset select setfenv setmetatable tonumber tostring type unpack xpcall
string table math os io coroutine debug bit
strsplit strjoin strtrim strfind strlen strlower strupper strsub strrep strbyte strchar strmatch strgsub gmatch gsub format tinsert tremove wipe tContains
CreateFrame UIParent GetTime hooksecurefunc InCombatLockdown UnitAffectingCombat IsLoggedIn SlashCmdList
C_Timer C_CVar C_Map C_QuestLog C_SuperTrack C_VoiceChat C_Minimap C_Texture Enum
GetCVar SetCVar GetCameraZoom CameraZoomIn CameraZoomOut
GameTooltip GameTooltip_SetTitle
Minimap MinimapCluster WorldMapFrame AddonCompartmentFrame MicroMenu MicroMenuContainer`.split(/\s+/));

if (process.env.LUA_STRICT) { const base = new Set(`_G _VERSION assert collectgarbage error getfenv getmetatable ipairs load loadstring next pairs pcall print rawequal rawget rawset select setfenv setmetatable tonumber tostring type unpack xpcall string table math os io coroutine debug bit`.split(/\s+/)); STD.clear(); base.forEach(n => STD.add(n)); }
const extra = process.env.LUA_GLOBALS ? process.env.LUA_GLOBALS.split(/[\s,]+/) : [];
extra.forEach(n => STD.add(n));

let bad = 0;
for (const file of process.argv.slice(2)) {
  const src = fs.readFileSync(file, 'utf8');
  let ast;
  try {
    ast = luaparse.parse(src, { luaVersion: '5.1', locations: true, comments: false });
  } catch (e) {
    console.log(`SYNTAX ${file}: ${e.message}`);
    bad++;
    continue;
  }
  const scopes = [new Set()];
  const unknown = new Map();
  const declare = n => scopes[scopes.length - 1].add(n);
  const isLocal = n => scopes.some(s => s.has(n));
  const noteGlobal = (n, line, w) => {
    if (isLocal(n) || STD.has(n)) return;
    const k = n;
    if (!unknown.has(k)) unknown.set(k, { lines: [], write: false });
    const u = unknown.get(k);
    if (u.lines.length < 4) u.lines.push(line);
    if (w) u.write = true;
  };
  function walk(node, asWrite) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(n => walk(n)); return; }
    switch (node.type) {
      case 'LocalStatement':
        node.init.forEach(n => walk(n));
        node.variables.forEach(v => declare(v.name));
        return;
      case 'FunctionDeclaration': {
        if (node.identifier) {
          if (node.isLocal) declare(node.identifier.name);
          else if (node.identifier.type === 'Identifier') noteGlobal(node.identifier.name, node.loc.start.line, true);
          else walk(node.identifier);
        }
        scopes.push(new Set());
        if (node.identifier && node.identifier.type === 'MemberExpression' && node.identifier.indexer === ':') declare('self');
        node.parameters.forEach(p => { if (p.type === 'Identifier') declare(p.name); });
        walk(node.body);
        scopes.pop();
        return;
      }
      case 'ForNumericStatement':
        walk(node.start); walk(node.end); walk(node.step);
        scopes.push(new Set()); declare(node.variable.name); walk(node.body); scopes.pop();
        return;
      case 'ForGenericStatement':
        walk(node.iterators);
        scopes.push(new Set()); node.variables.forEach(v => declare(v.name)); walk(node.body); scopes.pop();
        return;
      case 'DoStatement': case 'WhileStatement': case 'RepeatStatement': case 'IfClause': case 'ElseifClause': case 'ElseClause':
        if (node.condition) walk(node.condition);
        scopes.push(new Set()); walk(node.body); scopes.pop();
        return;
      case 'IfStatement':
        node.clauses.forEach(c => walk(c));
        return;
      case 'AssignmentStatement':
        node.init.forEach(n => walk(n));
        node.variables.forEach(v => {
          if (v.type === 'Identifier') noteGlobal(v.name, v.loc.start.line, true);
          else walk(v);
        });
        return;
      case 'Identifier':
        noteGlobal(node.name, node.loc.start.line, false);
        return;
      case 'TableKeyString':
        walk(node.value);
        return;
      case 'MemberExpression':
        walk(node.base); // identifier is a field name, not a variable
        return;
      case 'IndexExpression':
        walk(node.base); walk(node.index);
        return;
      default:
        for (const k of Object.keys(node)) {
          if (k === 'loc' || k === 'range' || k === 'type') continue;
          walk(node[k]);
        }
    }
  }
  walk(ast.body);
  console.log(`OK syntax ${file}`);
  for (const [n, u] of [...unknown.entries()].sort()) {
    console.log(`  global ${u.write ? 'WRITE' : 'read '} ${n}  (line ${u.lines.join(',')})`);
  }
}
process.exit(bad ? 1 : 0);
