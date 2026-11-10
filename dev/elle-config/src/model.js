// Turns an EllesmereUI settings tree (see luatable.js) into rectangles to draw,
// and writes edits back into the tree.
//
// The arithmetic follows what EllesmereUI does with these settings (learned by
// reading its source, v9.8.4, 2026-11-10). Nothing is copied from it: the
// default values below are the plain values its settings fall back to when a
// key is absent from the file, which is the only way to read a file that stores
// changed values only.
(function (root) {
  'use strict';
  const L = typeof require !== 'undefined' ? require('./luatable.js') : root.LuaTable;

  const SHAPES = ['none', 'cropped', 'square', 'circle', 'csquare', 'diamond', 'hexagon', 'portrait', 'shield'];
  const SHAPE_LABELS = {
    none: 'None', cropped: 'Cropped', square: 'Square', circle: 'Circle', csquare: 'Curved square',
    diamond: 'Diamond', hexagon: 'Hexagon', portrait: 'Portrait', shield: 'Shield',
  };
  const THICKNESS = ['none', 'thin', 'normal', 'heavy', 'strong'];
  const THICKNESS_PX = { none: 0, thin: 1, normal: 2, heavy: 3, strong: 4 };
  const isCustomShape = (s) => s !== 'none' && s !== 'cropped';

  // ---- action bars ---------------------------------------------------------
  const AB_BARS = [
    { key: 'MainBar', label: 'Action Bar 1 (Main)', count: 12 },
    { key: 'Bar2', label: 'Action Bar 2', count: 12 },
    { key: 'Bar3', label: 'Action Bar 3', count: 12 },
    { key: 'Bar4', label: 'Action Bar 4', count: 12 },
    { key: 'Bar5', label: 'Action Bar 5', count: 12 },
    { key: 'Bar6', label: 'Action Bar 6', count: 12 },
    { key: 'Bar7', label: 'Action Bar 7', count: 12 },
    { key: 'Bar8', label: 'Action Bar 8', count: 12 },
    { key: 'StanceBar', label: 'Stance Bar', count: 10, stance: true },
    { key: 'PetBar', label: 'Pet Bar', count: 10 },
  ];
  const AB_DEFAULTS = {
    buttonPadding: 2, buttonWidth: 0, buttonHeight: 0, growDirection: 'up',
    borderEnabled: true, borderSize: 1, borderThickness: 'thin', borderTexture: 'solid',
    buttonShape: 'none', shapeBorderEnabled: true, shapeBorderSize: 7,
    alwaysHidden: false, barVisibility: 'always', enabled: true,
  };
  const AB_BASE = 45;            // button size when buttonWidth/Height is 0
  const AB_SHAPE_EXPAND = 10;    // a custom shape makes each button this much larger
  const AB_ZOOM = { none: 5.5, cropped: 2, square: 6, circle: 6, csquare: 6, diamond: 6, hexagon: 6, portrait: 6, shield: 6 };

  // ---- cooldown manager ----------------------------------------------------
  const CDM_DEFAULT_BARS = [
    { key: 'cooldowns', name: 'Cooldowns', iconSize: 42, y: -275 },
    { key: 'utility', name: 'Utility', iconSize: 36, y: -320 },
    { key: 'buffs', name: 'Buffs', iconSize: 32, y: -365 },
  ];
  const CDM_DEFAULTS = {
    iconSize: 36, numRows: 1, spacing: 2, borderSize: 1, borderThickness: 'thin', borderTexture: 'solid',
    iconShape: 'none', iconZoom: 0.08, verticalOrientation: false, growDirection: 'CENTER',
    barVisibility: 'always', enabled: true,
  };
  const CDM_ZOOM = { none: 0.08, cropped: 0.04, square: 0.06, circle: 0.06, csquare: 0.06, diamond: 0.06, hexagon: 0.06, portrait: 0.06, shield: 0.06 };

  // ---- unit frames (context only, sizes are rough) ------------------------
  const UF_FRAMES = [
    { key: 'player', label: 'Player', w: 181, hh: 46, ph: 6 },
    { key: 'target', label: 'Target', w: 181, hh: 46, ph: 6 },
    { key: 'focus', label: 'Focus', w: 160, hh: 34, ph: 6 },
    { key: 'targettarget', label: 'Target of target', w: 101, hh: 25, ph: 0 },
    { key: 'pet', label: 'Pet', w: 101, hh: 25, ph: 0 },
  ];

  function db(vars) {
    const d = vars.get('EllesmereUIDB');
    if (!(d instanceof Map)) throw new Error('This file has no EllesmereUIDB table. Load EllesmereUI.lua from SavedVariables.');
    return d;
  }
  function profileName(vars) { return L.get(db(vars), 'activeProfile') || 'Default'; }
  function profileNames(vars) {
    const p = L.get(db(vars), 'profiles');
    return p instanceof Map ? [...p.keys()] : [];
  }
  function addon(vars, profile, name) { return L.get(db(vars), 'profiles', profile, 'addons', name); }
  function addonPath(profile, name) { return ['profiles', profile, 'addons', name]; }

  // Screen in UI units. WoW's UI is 768 units high at scale 1.
  function screen(vars, physW, physH) {
    const scale = L.get(db(vars), 'ppUIScale');
    const s = typeof scale === 'number' && scale > 0 ? scale : 1;
    const uiH = 768 / s;
    const pxPerUnit = physH / uiH;
    return { physW, physH, scale: s, scaleFromFile: typeof scale === 'number', uiH, uiW: physW / pxPerUnit, pxPerUnit, onePx: 1 / pxPerUnit };
  }

  // Where a frame of size w x h sits. `pos` holds the frame's own anchor point,
  // the screen point it hangs from, and the offset (y grows upward).
  // Returns the frame's top-left corner, measured from the screen's top-left.
  function place(pos, w, h, scr) {
    const pt = (pos && pos.point) || 'CENTER';
    const rel = (pos && pos.relPoint) || pt;
    let ax = scr.uiW / 2, ay = scr.uiH / 2;         // screen anchor, y up from bottom
    if (rel.includes('LEFT')) ax = 0; else if (rel.includes('RIGHT')) ax = scr.uiW;
    if (rel.includes('BOTTOM')) ay = 0; else if (rel.includes('TOP')) ay = scr.uiH;
    const px = ax + ((pos && pos.x) || 0), py = ay + ((pos && pos.y) || 0);
    let left = px - w / 2, bottom = py - h / 2;
    if (pt.includes('LEFT')) left = px; else if (pt.includes('RIGHT')) left = px - w;
    if (pt.includes('BOTTOM')) bottom = py; else if (pt.includes('TOP')) bottom = py - h;
    return { left, top: scr.uiH - bottom - h };
  }

  // The inverse: the offset to store so that the frame's top-left lands at left/top.
  function unplace(pos, left, top, w, h, scr) {
    const pt = (pos && pos.point) || 'CENTER';
    const rel = (pos && pos.relPoint) || pt;
    let ax = scr.uiW / 2, ay = scr.uiH / 2;
    if (rel.includes('LEFT')) ax = 0; else if (rel.includes('RIGHT')) ax = scr.uiW;
    if (rel.includes('BOTTOM')) ay = 0; else if (rel.includes('TOP')) ay = scr.uiH;
    const bottom = scr.uiH - top - h;
    let px = left + w / 2, py = bottom + h / 2;
    if (pt.includes('LEFT')) px = left; else if (pt.includes('RIGHT')) px = left + w;
    if (pt.includes('BOTTOM')) py = bottom; else if (pt.includes('TOP')) py = bottom + h;
    return { x: px - ax, y: py - ay };
  }

  function plainPos(m) {
    if (!(m instanceof Map)) return null;
    return { point: m.get('point'), relPoint: m.get('relPoint'), x: m.get('x') || 0, y: m.get('y') || 0 };
  }
  function merged(defaults, stored) {
    const o = Object.assign({}, defaults);
    if (stored instanceof Map) for (const [k, v] of stored) if (typeof k === 'string' && !(v instanceof Map)) o[k] = v;
    return o;
  }
  const snap = (v, onePx) => Math.floor(v / onePx + 0.5);

  function actionBars(vars, scr, profile) {
    const ab = addon(vars, profile, 'EllesmereUIActionBars');
    const out = [];
    for (const info of AB_BARS) {
      const stored = L.get(ab, 'bars', info.key);
      const s = merged(AB_DEFAULTS, stored);
      const pos = plainPos(L.get(ab, 'barPositions', info.key));
      const notes = [];

      let numIcons = s.overrideNumIcons || s.numIcons || info.count;
      if (numIcons < 1 || numIcons > info.count) numIcons = info.count;
      if (info.stance) notes.push('The game shows one button per stance or form you have; the preview uses the count set here.');
      let numRows = Math.max(1, s.overrideNumRows || s.numRows || 1);
      const stride = Math.ceil(numIcons / numRows);
      numRows = Math.ceil(numIcons / stride);
      const vertical = s.orientation === 'vertical';
      const grow = String(s.growDirection || 'up').toUpperCase();
      const shape = s.buttonShape || 'none';

      const sized = s.buttonWidth > 0 && s.buttonHeight > 0;
      if (!sized) notes.push('Button size is not in the file; the preview assumes ' + AB_BASE + '.');
      let bw = s.buttonWidth > 0 ? s.buttonWidth : AB_BASE;
      let bh = s.buttonHeight > 0 ? s.buttonHeight : AB_BASE;
      if (isCustomShape(shape)) { bw += AB_SHAPE_EXPAND; bh += AB_SHAPE_EXPAND; }
      if (shape === 'cropped') bh *= 0.8;
      const bwPx = snap(bw, scr.onePx), bhPx = snap(bh, scr.onePx), padPx = snap(s.buttonPadding, scr.onePx);
      bw = bwPx * scr.onePx; bh = bhPx * scr.onePx;
      const pad = padPx * scr.onePx;

      const cols = vertical ? numRows : stride;
      const rows = vertical ? stride : numRows;
      const w = Math.max((cols * bwPx + (cols - 1) * padPx) * scr.onePx, 1);
      const h = Math.max((rows * bhPx + (rows - 1) * padPx) * scr.onePx, 1);
      const rowsUpward = !vertical && (grow === 'UP' || grow === 'CENTER');

      const cells = [];
      for (let i = 0; i < numIcons; i++) {
        const col = vertical ? Math.floor(i / stride) : i % stride;
        const row = vertical ? i % stride : Math.floor(i / stride);
        const x = col * (bw + pad);
        const y = rowsUpward ? h - bh - row * (bh + pad) : row * (bh + pad);
        cells.push({ x, y, w: bw, h: bh, label: String(i + 1) });
      }

      const hidden = s.alwaysHidden === true || s.barVisibility === 'never' || s.enabled === false;
      const custom = isCustomShape(shape);
      const borderPx = custom
        ? (s.shapeBorderEnabled === false ? 0 : THICKNESS_PX[s.borderThickness] != null ? THICKNESS_PX[s.borderThickness] : 4)
        : (s.borderEnabled === false ? 0 : s.borderSize);
      let frame = null;
      if (pos) frame = place(pos, w, h, scr);
      else notes.push('This bar has no saved position (it was never moved), so the preview cannot place it.');

      out.push({
        id: 'ab:' + info.key, kind: 'actionbar', key: info.key, label: info.label, maxIcons: info.count,
        hidden, placed: !!frame, left: frame ? frame.left : 0, top: frame ? frame.top : 0, w, h, cells,
        shape, borderPx, pos, notes,
        settings: {
          numIcons, numRows: Math.max(1, s.overrideNumRows || s.numRows || 1), vertical,
          buttonWidth: s.buttonWidth > 0 ? s.buttonWidth : AB_BASE, buttonHeight: s.buttonHeight > 0 ? s.buttonHeight : AB_BASE,
          buttonPadding: s.buttonPadding, shape, borderThickness: s.borderThickness, borderSize: s.borderSize,
          borderTexture: s.borderTexture,
        },
      });
    }
    return out;
  }

  function cdmCount(vars, key) {
    const cache = L.get(db(vars), 'cdmCachedBarSizes');
    if (cache instanceof Map) {
      for (const perChar of cache.values()) {
        if (!(perChar instanceof Map)) continue;
        for (const perSpec of perChar.values()) {
          const n = perSpec instanceof Map ? perSpec.get(key) : undefined;
          if (typeof n === 'number' && n > 0) return n;
        }
      }
    }
    return undefined;
  }

  // previewCounts: { barKey: number } chosen in the page; never written to the file.
  function cdmBars(vars, scr, profile, previewCounts) {
    const cdm = addon(vars, profile, 'EllesmereUICooldownManager');
    const bars = L.get(cdm, 'cdmBars', 'bars');
    const out = [];
    const n = Math.max(CDM_DEFAULT_BARS.length, bars instanceof Map ? bars.size : 0);
    for (let idx = 1; idx <= n; idx++) {
      const stored = bars instanceof Map ? bars.get(idx) : undefined;
      const dflt = CDM_DEFAULT_BARS[idx - 1];
      if (!dflt && !(stored instanceof Map)) continue;
      const s = merged(Object.assign({}, CDM_DEFAULTS, dflt ? { key: dflt.key, name: dflt.name, iconSize: dflt.iconSize } : {}), stored);
      if (s.isGhostBar) continue;
      const notes = [];
      const key = s.key;
      const fromGame = cdmCount(vars, key);
      const count = Math.max(1, (previewCounts && previewCounts[key]) || fromGame || 6);
      notes.push(fromGame
        ? 'The number of icons depends on your spells. The file remembers ' + fromGame + ' for this bar.'
        : 'The number of icons depends on your spells; the file does not say how many. The preview count is a guess.');

      const grow = String(s.growDirection || 'CENTER').toUpperCase();
      const horiz = grow === 'RIGHT' || grow === 'LEFT' || (grow === 'CENTER' && !s.verticalOrientation);
      const numRows = Math.max(1, s.numRows || 1);
      const stride = Math.ceil(count / numRows);
      const effRows = Math.ceil(count / stride);
      const shape = s.iconShape || 'none';

      let iw = s.iconSize, ih = s.iconSize;
      const iwPx = snap(iw, scr.onePx);
      if (shape === 'cropped') {
        const pct = Math.min(25, Math.max(5, Number(s.iconCropPercent) || 10));
        ih = Math.floor(iwPx * (1 - 2 * pct / 100) + 0.5) * scr.onePx;
      }
      const ihPx = snap(ih, scr.onePx), spPx = snap(s.spacing, scr.onePx);
      iw = iwPx * scr.onePx; ih = ihPx * scr.onePx;
      const sp = spPx * scr.onePx;
      const cols = horiz ? stride : effRows, rows = horiz ? effRows : stride;
      const w = (cols * iwPx + (cols - 1) * spPx) * scr.onePx;
      const h = (rows * ihPx + (rows - 1) * spPx) * scr.onePx;

      const cells = [];
      for (let i = 0; i < count; i++) {
        const a = i % stride, b = Math.floor(i / stride);
        const inRow = Math.min(stride, count - b * stride);
        const centre = Math.floor((stride - inRow) * ((horiz ? iw : ih) + sp) / 2 + 0.5);
        const col = horiz ? a : b, row = horiz ? b : a;
        cells.push({
          x: col * (iw + sp) + (horiz ? centre : 0), y: row * (ih + sp) + (horiz ? 0 : centre), w: iw, h: ih, label: '',
        });
      }

      let pos = plainPos(L.get(cdm, 'cdmBarPositions', key));
      let attached = false;
      if (key === 'focuskick') { attached = true; notes.push('This bar follows the focus target\'s nameplate, so it has no fixed place on screen.'); }
      else if (s.anchorTo && s.anchorTo !== 'none') { attached = true; notes.push('This bar is attached to "' + s.anchorTo + '", so it has no position of its own.'); }
      if (!pos && !attached) {
        pos = { point: 'CENTER', relPoint: 'CENTER', x: 0, y: dflt ? dflt.y : 0 };
        notes.push('No saved position; the preview uses the default place.');
      }
      const frame = attached ? null : place(pos, w, h, scr);
      const hidden = s.barVisibility === 'never' || s.enabled === false;
      out.push({
        id: 'cdm:' + key, kind: 'cdm', key, index: idx, label: 'Cooldowns: ' + (s.name || key),
        hidden, placed: !!frame, left: frame ? frame.left : 0, top: frame ? frame.top : 0, w, h, cells,
        shape, borderPx: THICKNESS_PX[s.borderThickness] != null && isCustomShape(shape) ? THICKNESS_PX[s.borderThickness] : s.borderSize,
        pos, notes, previewCount: count,
        settings: {
          iconSize: s.iconSize, spacing: s.spacing, numRows, vertical: !!s.verticalOrientation, growDirection: grow,
          shape, borderThickness: s.borderThickness, borderSize: s.borderSize, borderTexture: s.borderTexture,
        },
      });
    }
    return out;
  }

  function unitFrames(vars, scr, profile) {
    const uf = addon(vars, profile, 'EllesmereUIUnitFrames');
    const out = [];
    for (const f of UF_FRAMES) {
      const pos = plainPos(L.get(uf, 'positions', f.key));
      if (!pos) continue;
      const st = L.get(uf, f.key);
      const num = (k, d) => (st instanceof Map && typeof st.get(k) === 'number' ? st.get(k) : d);
      const w = num('frameWidth', f.w), h = num('healthHeight', f.hh) + num('powerHeight', f.ph);
      const p = place({ point: pos.point || 'CENTER', relPoint: pos.relPoint || 'CENTER', x: pos.x, y: pos.y }, w, h, scr);
      out.push({
        id: 'uf:' + f.key, kind: 'context', key: f.key, label: f.label + ' frame', hidden: false, placed: true,
        left: p.left, top: p.top, w, h, cells: [], shape: 'none', borderPx: 1, pos,
        notes: ['Shown for orientation only. Size and anchor are rough, and it cannot be edited here yet.'],
      });
    }
    return out;
  }

  function elements(vars, scr, profile, previewCounts) {
    return [].concat(actionBars(vars, scr, profile), cdmBars(vars, scr, profile, previewCounts), unitFrames(vars, scr, profile));
  }

  // ---- edits ---------------------------------------------------------------
  function abBar(vars, profile, key) {
    const p = addonPath(profile, 'EllesmereUIActionBars').concat(['bars', key]);
    let t = L.get.apply(null, [db(vars)].concat(p));
    if (!(t instanceof Map)) { t = new Map(); L.set.apply(null, [db(vars)].concat(p, [t])); }
    return t;
  }
  function cdmBar(vars, profile, index) {
    const p = addonPath(profile, 'EllesmereUICooldownManager').concat(['cdmBars', 'bars', index]);
    let t = L.get.apply(null, [db(vars)].concat(p));
    if (!(t instanceof Map)) { t = new Map(); L.set.apply(null, [db(vars)].concat(p, [t])); }
    return t;
  }

  // Returns an error string when the edit is not allowed, otherwise undefined.
  function setShape(vars, profile, el, shape) {
    if (SHAPES.indexOf(shape) < 0) return 'Unknown shape ' + shape;
    if (isCustomShape(shape) && (el.settings.borderTexture || 'solid') !== 'solid') {
      return 'EllesmereUI only allows this shape when Border Style is Solid. This bar uses "' + el.settings.borderTexture + '". Change it in game first.';
    }
    if (el.kind === 'actionbar') {
      const b = abBar(vars, profile, el.key);
      b.set('iconZoom', AB_ZOOM[shape]);
      b.set('buttonShape', shape);
      if (isCustomShape(shape)) { b.set('borderThickness', 'strong'); b.set('shapeBorderSize', 7); b.set('shapeBorderEnabled', true); }
      else { b.set('borderThickness', 'thin'); b.set('borderSize', 1); b.set('borderEnabled', true); }
      const size = shape === 'cropped' ? 11 : 12;
      b.set('keybindFontSize', size); b.set('countFontSize', size);
      // Text offsets: only the plain case is mirrored. With a custom text anchor
      // EllesmereUI adds its own corner spacing, so those are left as they are.
      if (!b.get('keybindAnchor')) { b.set('keybindOffsetX', 0); b.set('keybindOffsetY', shape === 'cropped' ? 1 : 0); }
      if (!b.get('countAnchor')) { b.set('countOffsetX', 0); b.set('countOffsetY', shape === 'cropped' ? -1 : 0); }
    } else if (el.kind === 'cdm') {
      const b = cdmBar(vars, profile, el.index);
      b.set('iconShape', shape);
      b.set('iconZoom', CDM_ZOOM[shape]);
      if (isCustomShape(shape)) { b.set('borderThickness', 'strong'); b.set('borderSize', 4); b.set('activeStateAnim', 'blizzard'); }
      else { b.set('borderThickness', 'thin'); b.set('borderSize', 1); }
      for (const k of ['_matchIconPhys', '_matchExtraPixels', '_matchStride', '_matchExtraPixelsH', '_matchStrideH']) b.delete(k);
    } else return 'This element cannot be edited.';
  }

  function setField(vars, profile, el, field, value) {
    if (el.kind === 'actionbar') {
      const b = abBar(vars, profile, el.key);
      if (field === 'numIcons') b.set('overrideNumIcons', Math.min(el.maxIcons, Math.max(1, Math.round(value))));
      else if (field === 'numRows') b.set('overrideNumRows', Math.max(1, Math.round(value)));
      else if (field === 'vertical') { if (value) b.set('orientation', 'vertical'); else b.delete('orientation'); }
      else if (field === 'buttonWidth' || field === 'buttonHeight' || field === 'buttonPadding') b.set(field, Math.max(0, Number(value)));
      else if (field === 'hidden') {
        if (value) { b.set('alwaysHidden', true); b.set('barVisibility', 'never'); }
        else { b.delete('alwaysHidden'); b.set('barVisibility', 'always'); }
      } else if (field === 'borderThickness') {
        if (THICKNESS.indexOf(value) < 0) return 'Unknown thickness';
        b.set('borderThickness', value);
        if (!isCustomShape(el.shape)) { b.set('borderSize', THICKNESS_PX[value]); b.set('borderEnabled', value !== 'none'); }
        else b.set('shapeBorderEnabled', value !== 'none');
      } else return 'Unknown field ' + field;
    } else if (el.kind === 'cdm') {
      const b = cdmBar(vars, profile, el.index);
      if (field === 'iconSize') b.set('iconSize', Math.max(1, Number(value)));
      else if (field === 'spacing') b.set('spacing', Math.max(0, Number(value)));
      else if (field === 'numRows') b.set('numRows', Math.max(1, Math.round(value)));
      else if (field === 'vertical') b.set('verticalOrientation', !!value);
      else if (field === 'hidden') b.set('barVisibility', value ? 'never' : 'always');
      else if (field === 'borderThickness') {
        if (THICKNESS.indexOf(value) < 0) return 'Unknown thickness';
        b.set('borderThickness', value); b.set('borderSize', THICKNESS_PX[value]);
      } else return 'Unknown field ' + field;
    } else return 'This element cannot be edited.';
  }

  // Moves an element so its top-left corner lands at left/top (UI units).
  function moveTo(vars, profile, el, left, top, scr) {
    if (!el.placed || (el.kind !== 'actionbar' && el.kind !== 'cdm')) return 'This element cannot be moved here.';
    const pos = el.pos || { point: 'CENTER', relPoint: 'CENTER' };
    const lp = Math.round(left / scr.onePx) * scr.onePx, tp = Math.round(top / scr.onePx) * scr.onePx;
    const o = unplace(pos, lp, tp, el.w, el.h, scr);
    const path = el.kind === 'actionbar'
      ? addonPath(profile, 'EllesmereUIActionBars').concat(['barPositions', el.key])
      : addonPath(profile, 'EllesmereUICooldownManager').concat(['cdmBarPositions', el.key]);
    let t = L.get.apply(null, [db(vars)].concat(path));
    if (!(t instanceof Map)) {
      t = new Map([['point', pos.point || 'CENTER'], ['relPoint', pos.relPoint || 'CENTER']]);
      L.set.apply(null, [db(vars)].concat(path, [t]));
    }
    t.set('x', o.x); t.set('y', o.y);
  }

  // Lists what differs between two trees, as readable lines.
  function diff(a, b, path, out) {
    out = out || []; path = path || '';
    const keys = new Set();
    if (a instanceof Map) for (const k of a.keys()) keys.add(k);
    if (b instanceof Map) for (const k of b.keys()) keys.add(k);
    for (const k of keys) {
      const va = a instanceof Map ? a.get(k) : undefined, vb = b instanceof Map ? b.get(k) : undefined;
      const p = path ? path + '.' + k : String(k);
      if (va instanceof Map || vb instanceof Map) {
        if (va instanceof Map && vb instanceof Map) diff(va, vb, p, out);
        else if (vb instanceof Map) diff(new Map(), vb, p, out);
        else out.push({ path: p, from: '(table)', to: vb === undefined ? '(removed)' : vb });
      } else if (!Object.is(va, vb)) {
        out.push({ path: p, from: va === undefined ? '(not set)' : va, to: vb === undefined ? '(removed)' : vb });
      }
    }
    return out;
  }

  const api = {
    SHAPES, SHAPE_LABELS, THICKNESS, isCustomShape, AB_BARS,
    db, profileName, profileNames, screen, place, unplace, elements, actionBars, cdmBars, unitFrames,
    setShape, setField, moveTo, diff,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ElleModel = api;
})(typeof self !== 'undefined' ? self : this);
