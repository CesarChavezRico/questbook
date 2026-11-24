// Writes data/Layout.lua for the addon from plans/thara-cooldowns.js (4BI-51):
//   node dev/elle-config/emit-cooldowns.js <EllesmereUI.lua as it is now>
// The settings file is only read (the hidden bar's list, the number of bars, the lists that exist); never commit it.
//
// Unlike emit-layout.js this does not compare two files. It writes whole values (a bar's spell list, one spell's rule),
// so a list that changed in the game since the file was taken is replaced, not patched entry by entry.
//
// The guard: every value this writes is cooldown manager data. Two places hold it in EllesmereUI's settings:
//   spellAssignments.profiles.<profile>.specProfiles.<spec>.barSpells | spellSettingsCD     which spell on which bar, per-spell rules
//   profiles.<profile>.addons.EllesmereUICooldownManager.cdmBars | cdmBarPositions | customActiveStates
// Anything else is refused. Action buttons, macros and key bindings are not in this file at all: the game keeps them.
const fs = require('fs');
const path = require('path');
const L = require('./src/luatable.js');

const STATE = { cooldown: 'hiddenReadyShift', usable: 'hiddenUnusableShift' };
const FORMS = ['cat', 'bear', 'prowl'];

function allowed(p, spec) {
  const at = (i, v) => p[i] === v;
  if (at(0, 'spellAssignments') && at(1, 'profiles') && at(2, '$profile') && at(3, 'specProfiles') && at(4, spec)) {
    return (at(5, 'barSpells') && p.length === 8 && ['assignedSpells', 'customSpellIDs', 'buffDisplayOrder'].includes(p[7]))
      || (at(5, 'spellSettingsCD') && p.length === 7 && typeof p[6] === 'number');
  }
  if (at(0, 'profiles') && at(1, '$profile') && at(2, 'addons') && at(3, 'EllesmereUICooldownManager')) {
    return (at(4, 'cdmBars') && at(5, 'bars') && p.length === 7 && typeof p[6] === 'number')
      || (at(4, 'cdmBarPositions') && p.length === 6)
      || (at(4, 'customActiveStates') && p.length === 6 && typeof p[5] === 'number');
  }
  return false;
}

// plain JS -> the Map tables luatable writes; an array becomes a list from 1
function tbl(v) {
  if (Array.isArray(v)) return new Map(v.map((x, i) => [i + 1, tbl(x)]));
  if (v instanceof Map) return new Map([...v].map(([k, x]) => [k, tbl(x)]));
  if (v && typeof v === 'object') return new Map(Object.entries(v).map(([k, x]) => [k, tbl(x)]));
  return v;
}
const list = (m) => (m instanceof Map ? [...m.values()] : []);

function rule(s) {
  const r = {};
  if (s.when) {
    if (!STATE[s.when]) throw new Error(s.name + ': unknown when "' + s.when + '"');
    r.cdStateEffect = STATE[s.when];
  }
  if (s.form) {
    if (!FORMS.includes(s.form)) throw new Error(s.name + ': unknown form "' + s.form + '"');
    r.stanceBarHide = 'outShift:' + s.form; // hidden outside that page, the icons after it close the gap
  }
  return Object.keys(r).length ? r : null;
}

function build(beforeText, plan) {
  const db = L.parse(beforeText).get('EllesmereUIDB');
  const profile = L.get(db, 'activeProfile') || 'Default';
  const cdm = L.get(db, 'profiles', profile, 'addons', 'EllesmereUICooldownManager');
  const specProf = L.get(db, 'spellAssignments', 'profiles', profile, 'specProfiles', plan.spec);
  if (!(cdm instanceof Map) || !(specProf instanceof Map)) throw new Error('the settings file has no cooldown manager data for profile ' + profile + ', spec ' + plan.spec);
  const bars = list(L.get(cdm, 'cdmBars', 'bars'));
  const ghost = bars.find((b) => b.get('isGhostBar') === true);
  if (!ghost) throw new Error('no hidden bar in the settings file');
  const rot = plan.rotation;
  const at = bars.findIndex((b) => b.get('key') === rot.key);
  const barIndex = at >= 0 ? at + 1 : bars.length + 1;

  // every spell once
  const seen = new Map();
  const claim = (s, where) => {
    if (!Number.isInteger(s.id) || s.id <= 0) throw new Error(where + ': bad spell id for ' + s.name);
    if (seen.has(s.id)) throw new Error(s.name + ' (' + s.id + ') is listed twice: ' + seen.get(s.id) + ' and ' + where);
    seen.set(s.id, where);
  };
  for (const [bar, spells] of Object.entries(plan.rows)) for (const s of spells) { claim(s, bar); if (s.custom) throw new Error(s.name + ': a custom spell on a default bar is not written by this tool'); }
  for (const s of rot.spells) claim(s, rot.key);
  for (const s of plan.hidden) claim(s, 'hidden');

  const sets = [];
  const SPEC = ['spellAssignments', 'profiles', '$profile', 'specProfiles', plan.spec];
  const CDM = ['profiles', '$profile', 'addons', 'EllesmereUICooldownManager'];
  const put = (p, value) => {
    if (!allowed(p, plan.spec)) throw new Error('refused, not cooldown manager data: ' + p.join('.'));
    sets.push({ path: p, value: tbl(value) });
  };

  for (const [bar, spells] of Object.entries(plan.rows)) {
    if (!bars.some((b, i) => (b.get('key') || ['cooldowns', 'utility', 'buffs'][i]) === bar)) throw new Error('no bar "' + bar + '" in the settings file');
    put(SPEC.concat('barSpells', bar, 'assignedSpells'), spells.map((s) => s.id));
  }
  put(SPEC.concat('barSpells', rot.key, 'assignedSpells'), rot.spells.map((s) => s.id));
  const custom = rot.spells.filter((s) => s.custom);
  if (custom.length) put(SPEC.concat('barSpells', rot.key, 'customSpellIDs'), new Map(custom.map((s) => [s.id, true])));

  // the hidden bar holds exactly the plan's list. What it held and loses is reported: in Cesar's file of 2026-11-24 those
  // were old ranks (Moonfire, Faerie Fire, Rake), and an old rank of a spell the plan shows must not stay parked there.
  const ghostKey = ghost.get('key');
  const hiddenIds = plan.hidden.map((s) => s.id);
  const dropped = list(L.get(specProf, 'barSpells', ghostKey, 'assignedSpells')).filter((id) => !hiddenIds.includes(id));
  put(SPEC.concat('barSpells', ghostKey, 'assignedSpells'), hiddenIds);

  // rules: a native spell's live with the spec, a custom spell's with the profile
  for (const s of [].concat(...Object.values(plan.rows), rot.spells)) {
    const r = rule(s);
    if (!r) continue;
    if (s.custom) put(CDM.concat('customActiveStates', s.id), r);
    else put(SPEC.concat('spellSettingsCD', s.id), r);
  }

  // the buffs bar's order: the plan's first, then what was there
  const first = plan.buffsFirst.map((b) => 'c' + b.cd);
  const order = list(L.get(specProf, 'barSpells', 'buffs', 'buffDisplayOrder')).filter((t) => !first.includes(t));
  put(SPEC.concat('barSpells', 'buffs', 'buffDisplayOrder'), first.concat(order));

  // the new bar, in the look of the two that exist (circles, strong border)
  const look = bars[0];
  put(CDM.concat('cdmBars', 'bars', barIndex), {
    key: rot.key, name: rot.name, barType: 'cooldowns', enabled: true, numRows: 1,
    iconSize: rot.iconSize, spacing: look.get('spacing') || 2, growDirection: 'RIGHT',
    iconShape: look.get('iconShape') || 'none', iconZoom: look.get('iconZoom') || 0.08,
    borderThickness: look.get('borderThickness') || 'thin', borderSize: look.get('borderSize') || 1,
    borderR: 0, borderG: 0, borderB: 0, borderA: 1, borderClassColor: false,
    bgR: 0.08, bgG: 0.08, bgB: 0.08, bgA: 0.6, barBgEnabled: false, barBgR: 0, barBgG: 0, barBgB: 0,
    verticalOrientation: false, barVisibility: 'always', anchorTo: 'none', anchorPosition: 'left', anchorOffsetX: 0, anchorOffsetY: 0,
    showCooldownText: true, cooldownTextPosition: 'center', cooldownFontSize: 12, desaturateOnCD: true, swipeAlpha: 0.7,
    showCharges: true, chargeFontSize: 11, showItemCount: true, showStackCount: false, stackCountSize: 11,
    activeStateAnim: look.get('activeStateAnim') || 'blizzard', outOfRangeOverlay: false, pandemicGlow: false,
  });
  put(CDM.concat('cdmBarPositions', rot.key), rot.position);

  const pathLua = (p) => '{ ' + p.map((k) => L.lua(k)).join(', ') + ' }';
  const lines = [
    '-- GENERATED by dev/elle-config/emit-cooldowns.js from dev/elle-config/plans/thara-cooldowns.js. Do not edit by hand.',
    '-- The EllesmereUI layout: values to set in its saved settings, applied by /qb layout apply (modules/Loadout.lua).',
    '-- Cooldown manager data only (4BI-51): which spell sits on which cooldown bar, each spell\'s show/hide rule, one new bar.',
    'local _, QB = ...',
    'QB.layoutData = {',
    '  v = 1,',
    '  name = ' + L.lua(plan.name) + ',',
    '  sets = {',
  ];
  for (const s of sets) lines.push('    { path = ' + pathLua(s.path) + ', value = ' + L.lua(s.value).replace(/\n/g, ' ') + ' },');
  lines.push('  },', '  removes = {', '  },', '}', '');
  return { text: lines.join('\n'), sets, barIndex, profile, dropped };
}
module.exports = { build, allowed, rule };
if (require.main === module) {
  const before = process.argv[2];
  if (!before) { console.error('usage: node dev/elle-config/emit-cooldowns.js <EllesmereUI.lua>'); process.exit(2); }
  const r = build(fs.readFileSync(before, 'utf8'), require('./plans/thara-cooldowns.js'));
  fs.writeFileSync(path.join(__dirname, '..', '..', 'data', 'Layout.lua'), r.text);
  console.log('wrote data/Layout.lua:', r.sets.length, 'values; the new bar is bar', r.barIndex, 'of profile', r.profile);
  if (r.dropped.length) console.log('the hidden bar loses these ids (check they are old ranks):', r.dropped.join(', '));
}
