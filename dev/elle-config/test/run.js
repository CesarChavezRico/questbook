// Offline checks for the configurator: node dev/elle-config/test/run.js [path/to/EllesmereUI.lua]
// With a path, the file reader is also checked against that real file.
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const L = require('../src/luatable.js');
const M = require('../src/model.js');

let failed = 0;
const pending = [];
function test(name, fn) {
  const done = (err) => { if (err) { failed++; console.log('FAIL  ' + name + '\n      ' + (err.stack || err)); } else console.log('ok    ' + name); };
  try { const r = fn(); if (r && r.then) pending.push(r.then(() => done(), done)); else done(); } catch (e) { done(e); }
}
const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-6, (msg || '') + ' expected ' + b + ' got ' + a);
const text = fs.readFileSync(path.join(__dirname, 'fixture.txt'), 'utf8');
const fresh = () => L.parse(text);

// Real Lua (wasmoon) decides whether two files hold the same data.
async function sameInLua(a, b) {
  const { LuaFactory } = require('wasmoon');
  const lua = await new LuaFactory().createEngine();
  try {
    lua.global.set('SRC_A', a); lua.global.set('SRC_B', b);
    return await lua.doString(`
      local function env(src) local e = {}; local f = assert(load(src, 'sv', 't', e)); f(); return e end
      local function same(x, y)
        if type(x) ~= type(y) then return false end
        if type(x) ~= 'table' then return x == y end
        for k, v in pairs(x) do if not same(v, y[k]) then return false end end
        for k in pairs(y) do if x[k] == nil then return false end end
        return true
      end
      return same(env(SRC_A), env(SRC_B))`);
  } finally { lua.global.close(); }
}

test('reader: values, key types, positional entries, escapes', () => {
  const d = fresh().get('EllesmereUIDB');
  assert.strictEqual(d.get('note'), 'quote " backslash \\ newline \n tab\tend');
  assert.strictEqual(d.get(102), 'number key');
  assert.strictEqual(d.get('102'), 'string key');
  assert.strictEqual(L.get(d, 'list', 2), 'second');
  assert.strictEqual(L.get(d, 'list', 3, 'nested'), true);
  assert.strictEqual(d.get('ppUIScale'), 0.6399999856948853);
});
test('writer: read, write, read gives the same data', () => {
  const v = fresh();
  assert.ok(L.equal(v, L.parse(L.serialize(v))));
});
test('writer: real Lua loads the written file as the same data', async () => {
  assert.strictEqual(await sameInLua(text, L.serialize(fresh())), true);
});
test('writer: real Lua sees an edit', async () => {
  const v = fresh();
  L.set(v.get('EllesmereUIDB'), 'activeProfile', 'Other');
  assert.strictEqual(await sameInLua(text, L.serialize(v)), false);
});
test('reader: rejects a broken file', () => {
  assert.throws(() => L.parse('EllesmereUIDB = { ["a"] = '), /Lua parse error/);
});

test('screen: 3440x1440 at scale 0.64 is 1200 units high, 1.2 pixels per unit', () => {
  const s = M.screen(fresh(), 3440, 1440);
  // the saved scale is a 32-bit float, so these are close to, not exactly, the round numbers
  assert.ok(Math.abs(s.uiH - 1200) < 1e-3); assert.ok(Math.abs(s.pxPerUnit - 1.2) < 1e-6); assert.ok(Math.abs(s.uiW - 2866.6667) < 1e-3);
});
function byId(v, id, counts) {
  const s = M.screen(v, 3440, 1440);
  return { s, e: M.elements(v, s, 'Default', counts).find((x) => x.id === id) };
}
const px = (r) => ({ left: Math.round(r.e.left * r.s.pxPerUnit * 100) / 100, top: Math.round(r.e.top * r.s.pxPerUnit * 100) / 100, w: Math.round(r.e.w * r.s.pxPerUnit * 100) / 100, h: Math.round(r.e.h * r.s.pxPerUnit * 100) / 100 });

test('action bar: 12 buttons, vertical, 4 columns of 43 px with 2 px gaps', () => {
  const r = byId(fresh(), 'ab:MainBar');
  // 4 columns x 3 rows: width 4*43 + 3*2 = 178, height 3*43 + 2*2 = 133
  assert.deepStrictEqual(px(r), { left: 1387, top: 1099, w: 178, h: 133 });
  assert.strictEqual(r.e.cells.length, 12);
  near(r.e.cells[3].x * r.s.pxPerUnit, 45, 'button 4 starts the second column');
  near(r.e.cells[3].y, 0, 'button 4 is at the top');
});
test('action bar: one row of 12 at 54 px', () => {
  const r = byId(fresh(), 'ab:Bar3');
  assert.deepStrictEqual(px(r), { left: 2749, top: 1360, w: 670, h: 54 });
});
test('action bar: hidden and unplaced bars are flagged', () => {
  assert.strictEqual(byId(fresh(), 'ab:Bar4').e.hidden, true);
  const r = byId(fresh(), 'ab:Bar2');
  assert.strictEqual(r.e.placed, false);
  assert.ok(r.e.notes.some((n) => /no saved position/.test(n)));
});
test('cooldown bar: hangs from its left edge, count from the file', () => {
  const r = byId(fresh(), 'cdm:cooldowns');
  // 4 icons of 36 px with 10 px gaps = 174; left = 1720 - 251.666*1.2 = 1418
  assert.deepStrictEqual(px(r), { left: 1418, top: 1009, w: 174, h: 36 });
  assert.strictEqual(r.e.previewCount, 4);
});
test('cooldown bar: default place when none is saved, ghost bar skipped', () => {
  const v = fresh();
  const r = byId(v, 'cdm:utility');
  assert.strictEqual(r.e.previewCount, 5);
  near((r.e.top + r.e.h / 2) - r.s.uiH / 2, 320, 'centre is 320 units below the middle');
  assert.strictEqual(M.elements(v, r.s, 'Default').some((x) => x.key === '__ghost_cd'), false);
});
test('place and unplace are inverses for every anchor', () => {
  const s = M.screen(fresh(), 3440, 1440);
  for (const point of ['CENTER', 'LEFT', 'RIGHT', 'TOP', 'BOTTOM', 'TOPLEFT', 'BOTTOMRIGHT']) {
    for (const relPoint of ['CENTER', 'TOPLEFT', 'BOTTOM']) {
      const pos = { point, relPoint, x: 123.5, y: -77.25 };
      const p = M.place(pos, 200, 40, s);
      const o = M.unplace(pos, p.left, p.top, 200, 40, s);
      near(o.x, pos.x, point + '/' + relPoint + ' x'); near(o.y, pos.y, point + '/' + relPoint + ' y');
    }
  }
});

test('edit: hexagon on an action bar grows the buttons by 10 units and sets the border', () => {
  const v = fresh();
  let r = byId(v, 'ab:Bar3');
  assert.strictEqual(M.setShape(v, 'Default', r.e, 'hexagon'), undefined);
  r = byId(v, 'ab:Bar3');
  assert.strictEqual(r.e.shape, 'hexagon');
  assert.strictEqual(px(r).h, 66); // (45 + 10) units = 66 px
  const b = L.get(M.db(v), 'profiles', 'Default', 'addons', 'EllesmereUIActionBars', 'bars', 'Bar3');
  assert.strictEqual(b.get('borderThickness'), 'strong');
  assert.strictEqual(b.get('shapeBorderSize'), 7);
  assert.strictEqual(b.get('iconZoom'), 6);
});
test('edit: a custom shape is refused when the border style is not solid', () => {
  const v = fresh();
  const r = byId(v, 'cdm:cooldowns');
  assert.match(M.setShape(v, 'Default', r.e, 'circle'), /Border Style is Solid/);
  assert.strictEqual(byId(v, 'cdm:cooldowns').e.shape, 'none');
});
test('edit: circle on a cooldown bar', () => {
  const v = fresh();
  assert.strictEqual(M.setShape(v, 'Default', byId(v, 'cdm:utility').e, 'circle'), undefined);
  const b = L.get(M.db(v), 'profiles', 'Default', 'addons', 'EllesmereUICooldownManager', 'cdmBars', 'bars', 2);
  assert.strictEqual(b.get('iconShape'), 'circle');
  assert.strictEqual(b.get('borderSize'), 4);
  assert.strictEqual(b.get('iconZoom'), 0.06);
});
test('edit: moving keeps the anchor and lands on whole pixels', () => {
  const v = fresh();
  let r = byId(v, 'cdm:cooldowns');
  M.moveTo(v, 'Default', r.e, r.e.left + 10.3, r.e.top - 4.9, r.s);
  r = byId(v, 'cdm:cooldowns');
  assert.strictEqual(r.e.pos.point, 'LEFT');
  const p = px(r);
  assert.strictEqual(p.left, Math.round(p.left)); assert.strictEqual(p.top, Math.round(p.top));
  assert.strictEqual(p.left, 1418 + 12); assert.strictEqual(p.top, 1009 - 6);
});
test('edit: an unplaced bar cannot be moved', () => {
  const v = fresh();
  const r = byId(v, 'ab:Bar2');
  assert.match(M.moveTo(v, 'Default', r.e, 0, 0, r.s), /cannot be moved/);
});
test('edit: fields, and the list of changes', () => {
  const v = fresh();
  const r = byId(v, 'ab:Bar3');
  M.setField(v, 'Default', r.e, 'numRows', 2);
  M.setField(v, 'Default', r.e, 'hidden', true);
  const after = byId(v, 'ab:Bar3');
  assert.strictEqual(px(after).h, 54 * 2 + 2);
  assert.strictEqual(after.e.hidden, true);
  const d = M.diff(fresh().get('EllesmereUIDB'), v.get('EllesmereUIDB')).map((c) => c.path.split('.').pop()).sort();
  assert.deepStrictEqual(d, ['alwaysHidden', 'barVisibility', 'overrideNumRows']);
});
test('edit: an untouched file has no changes', () => {
  assert.strictEqual(M.diff(fresh().get('EllesmereUIDB'), fresh().get('EllesmereUIDB')).length, 0);
});

test('honeycomb: columns nest 3/4 of a button to the side and half a row down', () => {
  const v = fresh();
  const s = M.screen(v, 3440, 1440);
  const plan = M.handsPlan(v, s, 'Default', { size: 43 / s.pxPerUnit, gap: 0 });
  assert.strictEqual(M.honeycomb(v, 'Default', s, plan), undefined);
  const els = M.elements(v, s, 'Default');
  const P = (k) => { const e = els.find((x) => x.key === k); return { e, l: e.left * s.pxPerUnit, t: e.top * s.pxPerUnit, w: e.w * s.pxPerUnit, h: e.h * s.pxPerUnit }; };
  const idx = P('MainBar'), mid = P('Bar2'), ring = P('Bar4'), pinky = P('Bar5'), thumb = P('Bar6');
  // 43 px buttons become 55 px hexagons: columns 41 px apart, rows 46 px apart
  for (const b of [idx, mid, ring, pinky]) { assert.strictEqual(b.e.shape, 'hexagon'); assert.strictEqual(b.e.cells.length, 3); near(b.w, 55); near(b.h, 55 + 2 * 46); assert.strictEqual(b.e.hidden, false); }
  near(idx.l - mid.l, 41); near(mid.l - ring.l, 41); near(ring.l - pinky.l, 41);
  near(idx.t - mid.t, 23); near(ring.t - mid.t, 23); near(pinky.t, mid.t);
  near(thumb.l - idx.l, 41); near(thumb.t - mid.t, 2 * 46); assert.strictEqual(thumb.e.cells.length, 2);
  near(pinky.l, 1387, 'the block keeps the old left edge');
  // the two wheel tilts are one bar: a row of two, two columns apart, around the wheel column
  const tilt = P('Bar10'), wheel = P('Bar9');
  near(tilt.w, 55 + 82); near(wheel.l - tilt.l, 41); assert.strictEqual(tilt.e.hidden, false);
  for (const k of ['MainBar', 'Bar2', 'Bar4', 'Bar5', 'Bar6', 'Bar7', 'Bar8', 'Bar9', 'Bar10']) {
    const b = P(k); assert.ok(Math.abs(b.l - Math.round(b.l)) < 0.01 && Math.abs(b.t - Math.round(b.t)) < 0.01, k + ' is not on whole pixels');
  }
  assert.strictEqual(P('Bar3').e.shape, 'none', 'bar 3 is not touched');
});
test('honeycomb: bars 9 and 10 are hidden until used', () => {
  const v = fresh(), s = M.screen(v, 3440, 1440);
  assert.strictEqual(M.elements(v, s, 'Default').find((x) => x.key === 'Bar9').hidden, true);
});

test('map layouts: read the QuestBook map, keep every button off the map, stay on whole pixels', () => {
  const v = fresh(), s = M.screen(v, 3440, 1440);
  const qb = L.parse('QuestBookDB = { ["mod"] = { ["overlay"] = { ["cornerSize"] = 0.2, ["cornerX"] = -1314, ["cornerY"] = -784, ["corner"] = true } } }');
  const m = M.questbookMap(qb, s);
  near(m.side, 288); assert.ok(Math.abs(m.cx - 1719.2) < 0.1 && Math.abs(m.cy - 1084.8) < 0.1, 'map centre ' + m.cx + ',' + m.cy);
  for (const style of ['wings', 'crescent']) {
    const w = fresh();
    const plan = M.hugPlan(s, { style, sizePx: 43, gapPx: 0, map: { cx: m.cx, cy: m.cy, r: 121 }, marginPx: 8 });
    assert.strictEqual(M.layoutBars(w, 'Default', s, plan), undefined);
    const els = M.actionBars(w, s, 'Default');
    for (const b of plan.bars) {
      const e = els.find((x) => x.key === b.bar);
      assert.strictEqual(e.cells.length, b.n); assert.strictEqual(e.hidden, false);
      assert.strictEqual(e.shape, style === 'wings' ? 'hexagon' : 'circle');
      const l = e.left * s.pxPerUnit, t = e.top * s.pxPerUnit;
      assert.ok(Math.abs(l - Math.round(l)) < 0.01 && Math.abs(t - Math.round(t)) < 0.01, style + ' ' + b.bar + ' is not on whole pixels');
      for (const c of e.cells) {
        const cx = (e.left + c.x + c.w / 2) * s.pxPerUnit, cy = (e.top + c.y + c.h / 2) * s.pxPerUnit, r = c.w * s.pxPerUnit / 2;
        const d = Math.hypot(cx - m.cx, cy - m.cy);
        // a round button of radius r clears the map when its centre is r beyond the map's edge
        assert.ok(d >= 121 + (style === 'crescent' ? r : r * 0.8) - 1, style + ' ' + b.bar + ' button ' + c.label + ' overlaps the map: ' + d.toFixed(1));
      }
    }
    const thumbs = els.find((x) => x.key === 'Bar7');
    if (style === 'wings') {
      assert.strictEqual(thumbs.cells.length, 4, 'two, a gap, and one');
      assert.strictEqual(L.get(M.db(w), 'profiles', 'Default', 'addons', 'EllesmereUIActionBars', 'bars', 'Bar7', 'alwaysShowButtons'), false);
    } else {
      // circles: thumb up over thumb down, the index pair also upright, and a larger single button on its own bar
      const idx = els.find((x) => x.key === 'Bar8'), big = els.find((x) => x.key === 'Bar6');
      assert.strictEqual(thumbs.cells.length, 2); assert.ok(thumbs.h > thumbs.w * 1.9, 'thumb pair is upright');
      assert.ok(idx.h > idx.w * 1.9, 'index pair is upright');
      assert.strictEqual(big.cells.length, 1); assert.ok(big.w > thumbs.w * 1.15, 'the big button is bigger');
      assert.strictEqual(L.get(M.db(w), 'profiles', 'Default', 'addons', 'EllesmereUIActionBars', 'bars', 'Bar7', 'alwaysShowButtons'), true);
    }
  }
});

test('auras: EllesmereUI takes over buffs and debuffs, with a combat bar built from the lists in the file', () => {
  const v = fresh(), s = M.screen(v, 3440, 1440);
  const pab = new Map([['pabFilters', new Map([['list', new Map([
    [1, new Map([['id', 1], ['name', 'Defensives']])], [2, new Map([['id', 5], ['name', 'Offensive CDs']])], [3, new Map([['id', 6], ['name', 'Movement']])], [4, new Map([['id', 7], ['name', 'Utility']])],
  ])]])]]);
  L.set(M.db(v), 'profiles', 'Default', 'addons', 'EllesmereUIUnitFrames', 'playerAuraBars', pab);
  const plan = M.hugPlan(s, { style: 'crescent', sizePx: 43, gapPx: 0, map: { cx: 1720, cy: 1085, r: 121 }, marginPx: 8 });
  assert.deepStrictEqual(M.setupAuras(v, 'Default', s, plan.auras), []);
  assert.strictEqual(pab.get('enabled'), true);
  assert.strictEqual(pab.get('pabEditModeSeeded'), true);
  const combat = L.get(pab, 'customBuffBars', 1);
  assert.strictEqual(combat.get('showAllBuffs'), false);
  assert.deepStrictEqual([...combat.get('filters').keys()].sort(), [1, 5, 6]);
  assert.deepStrictEqual([...L.get(pab, 'defaultBuffs', 'negFilters').keys()].sort(), [1, 5, 6]);
  assert.strictEqual(pab.get('nextBarId'), 2);
  assert.strictEqual(L.get(pab, 'debuffsPos', 'point'), 'RIGHT');
  // building twice does not add a second combat bar
  M.setupAuras(v, 'Default', s, plan.auras);
  assert.strictEqual(pab.get('customBuffBars').size, 1);
  assert.strictEqual(L.get(M.db(v), 'profiles', 'Default', 'addons', 'EllesmereUIUnitFrames', 'target', 'onlyPlayerDebuffs'), true);
});

test('the built page is up to date with src/', () => {
  const b = require('../build.js');
  assert.strictEqual(fs.readFileSync(b.out, 'utf8'), b.build(), 'run: node dev/elle-config/build.js');
});

const real = process.argv[2];
if (real) {
  const t = fs.readFileSync(real, 'utf8');
  test('real file: read, write, read gives the same data', () => { const v = L.parse(t); assert.ok(L.equal(v, L.parse(L.serialize(v)))); });
  test('real file: real Lua loads the written file as the same data', async () => { assert.strictEqual(await sameInLua(t, L.serialize(L.parse(t))), true); });
  test('real file: every drawn element is on screen and on whole pixels', () => {
    const v = L.parse(t), s = M.screen(v, 3440, 1440);
    for (const e of M.elements(v, s, M.profileName(v))) {
      if (!e.placed || e.kind === 'context' || e.kind === 'unitframe') continue; // frame sizes are rough
      const l = e.left * s.pxPerUnit, tp = e.top * s.pxPerUnit;
      assert.ok(l >= 0 && tp >= 0 && l + e.w * s.pxPerUnit <= 3440 && tp + e.h * s.pxPerUnit <= 1440, e.id + ' is off screen');
      assert.ok(Math.abs(l - Math.round(l)) < 0.01 && Math.abs(tp - Math.round(tp)) < 0.01, e.id + ' is not on whole pixels: ' + l + ',' + tp);
    }
  });
}

Promise.all(pending).then(() => {
  console.log(failed ? failed + ' failed' : 'all passed');
  process.exit(failed ? 1 : 0);
});
