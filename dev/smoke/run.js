// usage: node run.js <addon-dir> scenario.lua [pre.lua]   (from dev/smoke)
// Loads the addon's TOC files into a Lua VM with a STUBBED WoW API (mock.lua) and runs a scenario.
// The stub treats unknown widget methods as no-ops, so this finds logic / nil / typo errors in OUR
// code, not whether a real Blizzard frame has a method. It is not a substitute for the game client.
const fs = require('fs'); const path = require('path');
const { LuaFactory } = require('wasmoon');
(async () => {
  const dir = process.argv[2];
  const scenario = fs.readFileSync(process.argv[3], 'utf8');
  const toc = fs.readFileSync(path.join(dir, 'QuestBook.toc'), 'utf8').split('\n')
    .map(l => l.trim()).filter(l => l && !l.startsWith('#'));
  const L = await new LuaFactory().createEngine();
  await L.doString(fs.readFileSync(path.join(__dirname, 'mock.lua'), 'utf8'));
  if (process.argv[4]) await L.doString(fs.readFileSync(process.argv[4], 'utf8'));
  await L.doString('__ns = {}');
  L.global.set('__readfile', f => { try { return fs.readFileSync(path.join(dir, f.replace(/\\/g, '/')), 'utf8'); } catch (e) { return ''; } });
  L.global.set('__tocfiles', toc.join('\n'));
  await L.doString(`
    __loaded, __missing = {}, {}
    for f in string.gmatch(__tocfiles, '[^\\n]+') do
      local src = __readfile(f)
      if not src or src == '' then __missing[#__missing+1] = f
      else
        local chunk, err = load(src, "@" .. f)
        if not chunk then error("load " .. f .. ": " .. tostring(err)) end
        chunk("QuestBook", __ns)
        __loaded[#__loaded+1] = f
      end
    end
    QB = __ns
  `);
  console.log('loaded:', await L.doString('return table.concat(__loaded, ", ")'), '| missing:', await L.doString('return table.concat(__missing, ", ")'));
  await L.doString(scenario);
  const lines = await L.doString('return table.concat(__take(), "\\n")');
  console.log(lines);
  const errs = await L.doString('local o = {} for n, r in pairs(QB.errors) do o[#o+1] = n .. " x" .. r.count .. ": " .. r.msg end return table.concat(o, "\\n")');
  console.log(errs ? '\nMODULE ERRORS:\n' + errs : '\nno module errors');
  process.exit(errs ? 1 : 0);
})().catch(e => { console.error('HARNESS FAIL:', e.message || e); process.exit(2); });
