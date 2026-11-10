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
    { key: 'Bar9', label: 'Action Bar 9', count: 12, hiddenByDefault: true },
    { key: 'Bar10', label: 'Action Bar 10', count: 12, hiddenByDefault: true },
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
      const s = merged(Object.assign({}, AB_DEFAULTS, info.hiddenByDefault ? { alwaysHidden: true, barVisibility: 'never' } : {}), stored);
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
        id: 'uf:' + f.key, kind: 'unitframe', key: f.key, label: f.label + ' frame', hidden: false, placed: true,
        left: p.left, top: p.top, w, h, cells: [], shape: 'none', borderPx: 1, pos,
        notes: ['The size drawn is rough (a portrait or extra bars are not counted). It can be moved, nothing else.'],
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
        else { b.set('alwaysHidden', false); b.set('barVisibility', 'always'); }
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
    if (el.kind === 'unitframe') {
      const lp = Math.round(left / scr.onePx) * scr.onePx, tp = Math.round(top / scr.onePx) * scr.onePx;
      const o = unplace({ point: 'CENTER', relPoint: 'CENTER' }, lp, tp, el.w, el.h, scr);
      // a position without an anchor is read by EllesmereUI as centre to centre
      L.set(db(vars), 'profiles', profile, 'addons', 'EllesmereUIUnitFrames', 'positions', el.key, new Map([['y', o.y], ['x', o.x]]));
      return undefined;
    }
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

  // ---- honeycomb -----------------------------------------------------------
  // EllesmereUI's hexagon has flat tops and points at the sides: the art spans
  // the full width of its button and about 84% of its height (measured on the
  // mask). Hexagons in one column touch along their flat edges; a neighbouring
  // column nests when it sits 3/4 of a button to the side and half a row down.
  // One bar can only be one column (or one spaced-out row), so a honeycomb is
  // built from several bars.
  const HEX_HEIGHT = 0.844;

  // plan: { size, gap (UI units), blocks: [{ anchor: {left|right, cy} in UI units from the
  //   screen's top-left, cells: [{ bar, n, col, row, dir: 'v'|'h', step }] }] }
  // 'v' is a column of n buttons; 'h' is a row of n buttons `step` columns apart.
  function honeycomb(vars, profile, scr, plan) {
    const one = scr.onePx;
    const sizePx = Math.max(8, Math.round(plan.size / one));
    const shapePx = sizePx + Math.round(AB_SHAPE_EXPAND / one);
    const gapPx = Math.round((plan.gap || 0) / one);
    const dxPx = Math.round(shapePx * 0.75) + gapPx;
    let dyPx = Math.round(shapePx * HEX_HEIGHT) + gapPx;
    if (dyPx % 2) dyPx += 1;                       // half rows must land on whole pixels
    const errors = [];
    const els = actionBars(vars, scr, profile);
    for (const block of plan.blocks) {
      const boxes = block.cells.map((c) => {
        const horizontal = c.dir === 'h';
        const pitch = horizontal ? (c.step || 2) * dxPx : dyPx;
        const padPx = pitch - shapePx;
        const long = c.n * shapePx + (c.n - 1) * padPx;
        return { c, horizontal, padPx, x: c.col * dxPx, y: Math.round(c.row * dyPx), w: horizontal ? long : shapePx, h: horizontal ? shapePx : long };
      });
      const minX = Math.min.apply(null, boxes.map((b) => b.x)), maxX = Math.max.apply(null, boxes.map((b) => b.x + b.w));
      const minY = Math.min.apply(null, boxes.map((b) => b.y)), maxY = Math.max.apply(null, boxes.map((b) => b.y + b.h));
      const a = block.anchor;
      const originX = a.right != null ? Math.round(a.right / one) - maxX : Math.round(a.left / one) - minX;
      const originY = Math.round(a.cy / one) - Math.round((minY + maxY) / 2);
      for (const b of boxes) {
        const el = els.find((e) => e.key === b.c.bar);
        if (!el) { errors.push('No action bar called ' + b.c.bar); continue; }
        const err = setShape(vars, profile, el, 'hexagon');
        if (err) { errors.push(el.label + ': ' + err); continue; }
        const t = abBar(vars, profile, el.key);
        t.set('overrideNumIcons', b.c.n); t.set('overrideNumRows', 1);
        if (b.horizontal) t.delete('orientation'); else t.set('orientation', 'vertical');
        t.set('buttonWidth', sizePx * one); t.set('buttonHeight', sizePx * one);
        t.set('buttonPadding', b.padPx * one);
        t.set('growDirection', 'center'); t.set('alwaysHidden', false); t.set('barVisibility', 'always');
        if (b.c.hideEmpty) t.set('alwaysShowButtons', false);
        const left = (originX + b.x) * one, top = (originY + b.y) * one, w = b.w * one, h = b.h * one;
        const o = unplace({ point: 'CENTER', relPoint: 'CENTER' }, left, top, w, h, scr);
        L.set(db(vars), 'profiles', profile, 'addons', 'EllesmereUIActionBars', 'barPositions', el.key,
          new Map([['point', 'CENTER'], ['relPoint', 'CENTER'], ['x', o.x], ['y', o.y]]));
      }
    }
    return errors.length ? errors.join('\n') : undefined;
  }

  // Cesar's two devices as honeycomb blocks. Left hand: a 4 x 3 key grid (pinky to
  // index, left to right) plus two thumb keys at the lower right. Right hand, a
  // G502 seen from above: three thumb buttons, the two index buttons beside the
  // left click, then the wheel (up, click, down) with a tilt on each side.
  // Bar 3 is left alone.
  function handsPlan(vars, scr, profile, opts) {
    const els = actionBars(vars, scr, profile);
    const find = (k) => els.find((e) => e.key === k);
    const main = find('MainBar'), bar2 = find('Bar2');
    const mid = scr.uiW / 2;
    const leftAnchor = main && main.placed ? { left: main.left, cy: main.top + main.h / 2 } : { left: mid - 320, cy: scr.uiH * 0.8 };
    const rightAnchor = bar2 && bar2.placed ? { right: bar2.left + bar2.w, cy: bar2.top + bar2.h / 2 } : { right: mid + 320, cy: scr.uiH * 0.8 };
    const hi = opts.flip ? 0.5 : 0, lo = opts.flip ? 0 : 0.5;
    return {
      size: opts.size, gap: opts.gap,
      blocks: [
        { anchor: leftAnchor, cells: [
          { bar: 'Bar5', n: 3, col: 0, row: hi, dir: 'v', seat: 'pinky column' },
          { bar: 'Bar4', n: 3, col: 1, row: lo, dir: 'v', seat: 'ring column' },
          { bar: 'Bar2', n: 3, col: 2, row: hi, dir: 'v', seat: 'middle column' },
          { bar: 'MainBar', n: 3, col: 3, row: lo, dir: 'v', seat: 'index column' },
          { bar: 'Bar6', n: 2, col: 4, row: hi + 2, dir: 'v', seat: 'left thumb keys' },
        ] },
        { anchor: rightAnchor, cells: [
          { bar: 'Bar7', n: 4, col: 0, row: hi, dir: 'v', hideEmpty: true, empty: [3], seat: 'mouse thumb buttons: 1 and 2 are the pair, 4 is the single one, 3 stays empty' },
          { bar: 'Bar8', n: 2, col: 1, row: lo, dir: 'v', seat: 'index buttons (front, rear)' },
          { bar: 'Bar10', n: 2, col: 2, row: hi + 1, dir: 'h', step: 2, seat: 'wheel tilt left and right' },
          { bar: 'Bar9', n: 3, col: 3, row: lo, dir: 'v', seat: 'wheel up, click, down' },
        ] },
      ],
    };
  }

  // ---- layouts around the centre map -----------------------------------------
  // QuestBook's small minimap (its saved file, QuestBook.lua): a square whose side
  // is a fraction of the screen height, hung by its top-right corner from the
  // screen's top-right corner. Returned in screen pixels.
  function questbookMap(qbVars, scr) {
    const o = L.get(qbVars.get('QuestBookDB'), 'mod', 'overlay');
    if (!(o instanceof Map)) return null;
    const num = (k, d) => (typeof o.get(k) === 'number' ? o.get(k) : d);
    const side = Math.max(48, Math.min(0.5, Math.max(0.05, num('cornerSize', 0.16))) * scr.uiH);
    const right = scr.uiW + num('cornerX', -24), top = -num('cornerY', -44);
    const ppu = scr.pxPerUnit;
    return { cx: (right - side / 2) * ppu, cy: (top + side / 2) * ppu, side: side * ppu, shown: o.get('corner') !== false };
  }

  // Writes a list of bars given in whole screen pixels:
  // spec { sizePx, shape, bars: [{ bar, n, dir: 'v'|'h', x, y, pitchPx, hideEmpty }] }
  function layoutBars(vars, profile, scr, spec) {
    const one = scr.onePx, errors = [];
    const els = actionBars(vars, scr, profile);
    const drawn = spec.sizePx + (isCustomShape(spec.shape) ? Math.round(AB_SHAPE_EXPAND / one) : 0);
    for (const b of spec.bars) {
      const el = els.find((e) => e.key === b.bar);
      if (!el) { errors.push('No action bar called ' + b.bar); continue; }
      const err = setShape(vars, profile, el, spec.shape);
      if (err) { errors.push(el.label + ': ' + err); continue; }
      const t = abBar(vars, profile, el.key);
      t.set('overrideNumIcons', b.n); t.set('overrideNumRows', 1);
      if (b.dir === 'h') t.delete('orientation'); else t.set('orientation', 'vertical');
      t.set('buttonWidth', spec.sizePx * one); t.set('buttonHeight', spec.sizePx * one);
      t.set('buttonPadding', (b.pitchPx - drawn) * one);
      t.set('growDirection', 'center'); t.set('alwaysHidden', false); t.set('barVisibility', 'always');
      if (b.hideEmpty) t.set('alwaysShowButtons', false);
      const long = b.n * drawn + (b.n - 1) * (b.pitchPx - drawn);
      const w = (b.dir === 'h' ? long : drawn) * one, h = (b.dir === 'h' ? drawn : long) * one;
      const o = unplace({ point: 'CENTER', relPoint: 'CENTER' }, Math.round(b.x) * one, Math.round(b.y) * one, w, h, scr);
      L.set(db(vars), 'profiles', profile, 'addons', 'EllesmereUIActionBars', 'barPositions', el.key,
        new Map([['point', 'CENTER'], ['relPoint', 'CENTER'], ['x', o.x], ['y', o.y]]));
    }
    return errors.length ? errors.join('\n') : undefined;
  }

  // Two ways to wrap the keypad and the mouse around a round map in the middle.
  // opts: { style: 'wings'|'crescent', sizePx, gapPx, map: { cx, cy, r }, marginPx } in screen pixels.
  function hugPlan(scr, opts) {
    const one = scr.onePx, exp = Math.round(AB_SHAPE_EXPAND / one);
    const S = opts.sizePx + exp, gap = opts.gapPx || 0;
    const mx = Math.round(opts.map.cx), my = Math.round(opts.map.cy), reach = opts.map.r + (opts.marginPx || 0);
    const bars = [];
    if (opts.style === 'wings') {
      // Hexagons. Every finger is a column; each column sits half a row higher than
      // the one nearer the map, so the two hands rise away from it like wings.
      const dx = Math.round(S * 0.75) + gap;
      let dy = Math.round(S * HEX_HEIGHT) + gap; if (dy % 2) dy += 1;
      const half = dy / 2, colH = (n) => (n - 1) * dy + S;
      const xi = mx - reach - S, y0 = my - Math.round(colH(3) / 2);
      [['MainBar', 'index column'], ['Bar2', 'middle column'], ['Bar4', 'ring column'], ['Bar5', 'pinky column']].forEach((c, k) => {
        bars.push({ bar: c[0], n: 3, dir: 'v', x: xi - k * dx, y: y0 - k * half, pitchPx: dy, seat: c[1] });
      });
      // the two thumb keys go under the map, on the first free honeycomb rows
      const tx = xi + dx, near = mx >= tx && mx <= tx + S ? 0 : Math.min(Math.abs(mx - tx), Math.abs(mx - tx - S));
      const clear = my + Math.sqrt(Math.max(0, reach * reach - near * near)) - S * (1 - HEX_HEIGHT) / 2;
      let ty = y0 + half; while (ty < clear - 8) ty += dy;   // 8 px of the margin may be given up to stay one row closer
      bars.push({ bar: 'Bar6', n: 2, dir: 'v', x: tx, y: ty, pitchPx: dy, seat: 'left thumb keys' });
      const xr = mx + reach, y0r = my - Math.round(colH(4) / 2);
      bars.push({ bar: 'Bar7', n: 4, dir: 'v', x: xr, y: y0r, pitchPx: dy, hideEmpty: true, empty: [3], seat: 'mouse thumb buttons: 1 and 2 are the pair, 4 is the single one, 3 stays empty' });
      bars.push({ bar: 'Bar8', n: 2, dir: 'v', x: xr + dx, y: y0r - half, pitchPx: dy, seat: 'index buttons (front, rear)' });
      bars.push({ bar: 'Bar10', n: 2, dir: 'h', x: xr + 2 * dx, y: y0r - dy, pitchPx: 2 * dx, seat: 'wheel tilt left and right' });
      bars.push({ bar: 'Bar9', n: 3, dir: 'v', x: xr + 3 * dx, y: y0r - dy - half, pitchPx: dy, seat: 'wheel up, click, down' });
      return { shape: 'hexagon', sizePx: opts.sizePx, bars };
    }
    // Circles. The player and target frames sit on the map's middle line, left and
    // right of it. Below them the keys wrap the lower half of the map: each key row is
    // a bar whose inner end follows the circle, and the lowest rows run under it. Above
    // the frames the cooldown rows do the same around the upper half.
    const p = S + gap, rho = reach + S / 2, centre = S / 2 + 3;
    const fr = opts.frames || { player: { w: 298, h: 80 }, target: { w: 217, h: 62 } };
    const band = Math.max(fr.player.h, fr.target.h) / 2 + 6;         // half height kept free for the frames
    const bandUp = band + (opts.nameAbovePx || 0);                    // above, the name floats over the bar
    const first = Math.round(band + S / 2);
    const inner = (off) => Math.max(centre, Math.abs(off) < rho ? Math.sqrt(rho * rho - off * off) : 0);
    const keys = ['P', 'R', 'M', 'I'];
    [['Bar2', 'top key row (pinky to index)'], ['MainBar', 'home key row (pinky to index)'], ['Bar4', 'bottom key row (pinky to index)']].forEach((c, r) => {
      const off = first + r * p;
      bars.push({ bar: c[0], n: 4, dir: 'h', x: mx - inner(off) + S / 2 - (3 * p + S), y: my + off - S / 2, pitchPx: p, seat: c[1], labels: keys });
    });
    const tOff = first + 3 * p;
    bars.push({ bar: 'Bar5', n: 2, dir: 'h', x: mx - inner(tOff) + S / 2 - (p + S), y: my + tOff - S / 2, pitchPx: p, seat: 'left thumb keys', labels: ['Th', 'Th'] });
    // the mouse mirrors the keypad: the wheel cross under the target frame with its left
    // tilt on the circle, the index pair under the map beside the wheel's down button, and
    // the thumb buttons on the lowest row (the pair, a gap, the single one)
    const wheelX = inner(first + p) + p;
    bars.push({ bar: 'Bar9', n: 3, dir: 'v', x: mx + wheelX - S / 2, y: my + first - S / 2, pitchPx: p, seat: 'wheel up, click, down', labels: ['Up', 'Clk', 'Dn'] });
    bars.push({ bar: 'Bar10', n: 2, dir: 'h', x: mx + wheelX - p - S / 2, y: my + first + p - S / 2, pitchPx: 2 * p, seat: 'wheel tilt left and right, either side of the wheel click', labels: ['<', '>'] });
    const idxX = Math.min(inner(first + 2 * p), wheelX - 2 * p);
    bars.push({ bar: 'Bar8', n: 2, dir: 'h', x: mx + idxX - S / 2, y: my + first + 2 * p - S / 2, pitchPx: p, seat: 'index buttons (front, rear)', labels: ['IF', 'IR'] });
    bars.push({ bar: 'Bar7', n: 4, dir: 'h', x: mx + inner(tOff) - S / 2, y: my + tOff - S / 2, pitchPx: p, hideEmpty: true, empty: [3], seat: 'mouse thumb buttons: 1 and 2 are the pair, 4 is the single one, 3 stays empty', labels: ['Th1', 'Th2', '', 'Th3'] });
    const frames = [
      { key: 'player', left: mx - reach - fr.player.w, top: my - fr.player.h / 2 },
      { key: 'target', left: mx + reach, top: my - fr.target.h / 2 },
    ];
    // The upper half mirrors the lower one: short rows on levels that step inward as they
    // go up, and a cap centred on top. Level 0 sits just above the frame names.
    // Cooldown manager rows are placed by placeAround; the rest are other EllesmereUI
    // elements this tool cannot move yet, drawn as dashed placeholders.
    const icon = 36, pitch = icon + 2, rhoI = reach + icon / 2;
    const levelOff = (k) => bandUp + icon / 2 + k * pitch;
    const levelDx = (k) => Math.max(icon / 2 + 3, levelOff(k) < rhoI ? Math.sqrt(rhoI * rhoI - levelOff(k) * levelOff(k)) : 0);
    const capOff = Math.max(rhoI, levelOff(2) + pitch);
    const dome = { iconPx: icon, levelOff: [0, 1, 2].map(levelOff), levelDx: [0, 1, 2].map(levelDx), capOff };
    // Three rows on each side. Left, about you: debuffs on you, tracked buffs, combat
    // buffs. Right, about the fight: your debuffs on the target, Cooldowns, Utility.
    // On top of the circle: combo points, then rage or energy, then the cast bar.
    const cdm = [
      { key: 'buffs', side: 'left', level: 1 }, { key: 'cooldowns', side: 'right', level: 1 }, { key: 'utility', side: 'right', level: 2 },
    ];
    const capW = 200, capBase = levelOff(2) + icon / 2 + 4;    // just above the highest rows
    // The power bar shows the current resource: energy or rage in a form, mana in caster
    // form, which is when the cast bar above it appears.
    const stack = [['secondary', 'combo points', 14], ['primary', 'energy / rage (mana while casting)', 12], ['castBar', 'cast bar', 16]];
    const resources = []; let up = capBase;
    for (const [key, label, h] of stack) { resources.push({ key, label, w: capW, h, cx: mx, cy: my - up - h / 2 }); up += h + 3; }
    const ghostRow = (label, side, level, n) => {
      const cells = [];
      for (let i = 0; i < n; i++) cells.push({ cx: mx + (side === 'left' ? -1 : 1) * (levelDx(level) + i * pitch), cy: my - levelOff(level), r: icon / 2 });
      return { label, side, cells };
    };
    const corner = { label: 'all other buffs (long-term)', side: 'left', cells: [] };
    for (let i = 0; i < 8; i++) corner.cells.push({ cx: scr.physW - 29 - icon / 2 - i * pitch, cy: 53 + 40 + icon / 2, r: icon / 2 });
    const planned = [
      ghostRow('debuffs on you', 'left', 0, 5), ghostRow('your debuffs on the target', 'right', 0, 5),
      ghostRow('your combat buffs', 'left', 2, 5), corner,
    ];
    const auras = {
      iconPx: icon, pitchPx: pitch,
      debuffs: { right: mx - levelDx(0) + icon / 2, cy: my - levelOff(0), n: 6 },
      combat: { right: mx - levelDx(2) + icon / 2, cy: my - levelOff(2), n: 6 },
      rest: { right: scr.physW - 29, top: 53 + 40, n: 12 },
      targetLift: bandUp - band + 2,
    };
    for (const r of resources) planned.push({ label: r.label, side: 'right', bar: { x: r.cx - r.w / 2, y: r.cy - r.h / 2, w: r.w, h: r.h, pips: r.key === 'secondary' ? 5 : 0 }, cells: [] });
    return { shape: 'circle', sizePx: opts.sizePx, bars, frames, cdm, reach, dome, planned, auras, resources };
  }

  // Makes the player and target frames a thin line with the name floating above it.
  // The in-game slider for the health bar stops at 15; EllesmereUI's own resize code
  // allows 8. Values are UI units.
  function slimFrames(vars, profile, healthH, powerH, lift) {
    for (const k of ['player', 'target']) {
      const set = (f, v) => L.set(db(vars), 'profiles', profile, 'addons', 'EllesmereUIUnitFrames', k, f, v);
      set('healthHeight', healthH); set('powerHeight', powerH);
      set('leftTextY', lift); set('rightTextY', lift);
    }
  }

  // Hands the player's buffs and debuffs to EllesmereUI's Player Aura Bars (off by
  // default, so the game's own buff frames were drawing them) and places them:
  //  - Debuffs: a row next to the player frame, growing away from the map.
  //  - "Combat buffs": a new bar showing only the Defensives, Offensive CDs and Movement lists.
  //  - Buffs: everything except those lists, in the top-right corner.
  // On the target frame, only your own debuffs, above the frame. All sizes in screen pixels.
  function setupAuras(vars, profile, scr, a) {
    const ppu = scr.pxPerUnit, notes = [];
    const uf = ['profiles', profile, 'addons', 'EllesmereUIUnitFrames'];
    const at = (path) => {
      let t = db(vars);
      for (const k of uf.concat(path)) { let nx = t.get(k); if (!(nx instanceof Map)) { nx = new Map(); t.set(k, nx); } t = nx; }
      return t;
    };
    const pab = at(['playerAuraBars']);
    pab.set('enabled', true);
    pab.set('pabEditModeSeeded', true);       // otherwise the first run copies the game's own buff frame places over these
    const SHAPE_GROW = 8;                     // a shaped aura icon is drawn this many units larger
    const size = a.iconPx / ppu - SHAPE_GROW, pad = (a.pitchPx - a.iconPx) / ppu;
    const row = (t, n, rows) => {
      t.set('iconSize', size); t.set('padding', pad); t.set('iconShape', 'circle');
      t.set('iconsPerRow', n); t.set('maxRows', rows); t.set('maxTotal', n * rows); t.set('growDirection', 'LEFT');
    };
    // a position that hangs the row's right end at a screen point; design = the row's nominal size is meant
    const hang = (rightPx, cyPx) => new Map([['point', 'RIGHT'], ['relPoint', 'CENTER'], ['x', (rightPx - scr.physW / 2) / ppu], ['y', (scr.physH / 2 - cyPx) / ppu], ['design', true]]);

    const lists = [];
    const reg = L.get(pab, 'pabFilters', 'list');
    if (reg instanceof Map) for (const f of reg.values()) if (f instanceof Map && ['Defensives', 'Offensive CDs', 'Movement'].indexOf(f.get('name')) >= 0) lists.push(f.get('id'));
    if (lists.length < 3) notes.push('Only ' + lists.length + ' of the 3 buff lists (Defensives, Offensive CDs, Movement) exist in the file, so the combat bar may be thin.');

    row(at(['playerAuraBars', 'defaultDebuffs']), a.debuffs.n, 1);
    pab.set('debuffsPos', hang(a.debuffs.right, a.debuffs.cy));

    const rest = at(['playerAuraBars', 'defaultBuffs']);
    row(rest, a.rest.n, 2);
    rest.set('negFilters', new Map(lists.map((id) => [id, true])));
    pab.set('buffsPos', new Map([['point', 'TOPRIGHT'], ['relPoint', 'TOPRIGHT'], ['x', (a.rest.right - scr.physW) / ppu], ['y', -a.rest.top / ppu], ['design', true]]));

    let bars = pab.get('customBuffBars');
    if (!(bars instanceof Map)) { bars = new Map(); pab.set('customBuffBars', bars); }
    let combat = [...bars.values()].find((b) => b instanceof Map && b.get('name') === 'Combat buffs');
    if (!combat) {
      const id = typeof pab.get('nextBarId') === 'number' ? pab.get('nextBarId') : 1;
      pab.set('nextBarId', id + 1);
      combat = new Map([['id', id], ['name', 'Combat buffs'], ['enabled', true], ['spells', new Map()], ['ownOnlySpells', new Map()]]);
      bars.set(bars.size + 1, combat);
    }
    combat.set('showAllBuffs', false);        // show only the lists below
    combat.set('filters', new Map(lists.map((id) => [id, true])));
    row(combat, a.combat.n, 1);
    combat.set('pos', hang(a.combat.right, a.combat.cy));

    const target = at(['target']);
    target.set('onlyPlayerDebuffs', true); target.set('debuffAnchor', 'topleft'); target.set('debuffOffsetY', a.targetLift / ppu);
    target.set('debuffSize', a.iconPx / ppu); target.set('maxDebuffs', 6);
    target.set('buffAnchor', 'topright'); target.set('buffOffsetY', a.targetLift / ppu);
    return notes;
  }

  // Turns on EllesmereUI's resource bars (off by default on this client) and stacks them
  // with the cast bar on top of the map. Each is stored as a centre-to-centre position.
  function setupResources(vars, profile, scr, items) {
    const ppu = scr.pxPerUnit;
    // Druid on this client: the player frame's power line stays on mana in bear and cat
    // (the "Power Type: Mana" choice of the player frame).
    L.set(db(vars), 'profiles', profile, 'addons', 'EllesmereUIUnitFrames', 'player', 'powerTypeOverride', 'foreverDruid', true);
    for (const r of items) {
      const path = ['profiles', profile, 'addons', 'EllesmereUIResourceBars', r.key];
      const set = (k, v) => L.set.apply(null, [db(vars)].concat(path, [k, v]));
      set('enabled', true);
      if (r.key === 'secondary') { set('pipWidth', r.w / ppu); set('pipHeight', r.h / ppu); }
      else { set('width', r.w / ppu); set('height', r.h / ppu); }
      set('unlockPos', new Map([['point', 'CENTER'], ['relPoint', 'CENTER'], ['x', (r.cx - scr.physW / 2) / ppu], ['y', (scr.physH / 2 - r.cy) / ppu]]));
    }
  }

  // Turns EllesmereUI's reskin of the map and quest log window on or off. With it off the
  // window is the game's own again. Kept in step with the saved copy of the active style.
  function setMapSkin(vars, on) {
    const d = db(vars);
    d.set('reskinWorldMap', on);
    const active = L.get(d, 'windowSkinStyleSlots', 'active');
    const slot = typeof active === 'string' ? L.get(d, 'windowSkinStyleSlots', active) : null;
    if (slot instanceof Map) slot.set('reskinWorldMap', on);
  }

  // Applies the frame and cooldown-row places of a plan made by hugPlan.
  function placeAround(vars, profile, scr, plan, map, counts) {
    const ppu = scr.pxPerUnit, skipped = [];
    for (const f of plan.frames || []) {
      const e = unitFrames(vars, scr, profile).find((x) => x.key === f.key);
      if (!e) continue;
      const tot = f.key === 'target' ? unitFrames(vars, scr, profile).find((x) => x.key === 'targettarget') : null;
      moveTo(vars, profile, e, f.left / ppu, f.top / ppu, scr);
      // the target of target goes to the far side of the target, out of the keys' way
      if (tot) moveTo(vars, profile, tot, f.left / ppu + e.w + 6 / ppu, f.top / ppu, scr);
    }
    for (const c of plan.cdm || []) {
      let e = cdmBars(vars, scr, profile, counts).find((x) => x.key === c.key);
      if (!e || !e.placed) continue;
      if (setShape(vars, profile, e, plan.shape)) {
        // shapes need a solid border; switch the style and try again
        cdmBar(vars, profile, e.index).set('borderTexture', 'solid');
        e = cdmBars(vars, scr, profile, counts).find((x) => x.key === c.key);
        if (setShape(vars, profile, e, plan.shape)) skipped.push(e.label); else skipped.push(e.label + ' (border style changed to Solid)');
      }
      // every row of the dome uses the same icon size and gap
      { const bar = cdmBar(vars, profile, e.index); bar.set('iconSize', plan.dome.iconPx / ppu); bar.set('spacing', 2 / ppu); }
      e = cdmBars(vars, scr, profile, counts).find((x) => x.key === c.key);
      const w = e.w * ppu, h = e.h * ppu, icon = e.cells.length ? e.cells[0].w * ppu : h, d = plan.dome;
      let left, top;
      if (c.side === 'cap') { left = map.cx - w / 2; top = map.cy - d.capOff - h / 2; }
      else {
        // the first icon's centre sits where a dome icon of this level would
        const dxc = d.levelDx[c.level] + (icon - d.iconPx) / 2;
        top = map.cy - d.levelOff[c.level] - h / 2;
        left = c.side === 'right' ? map.cx + dxc - icon / 2 : map.cx - dxc + icon / 2 - w;
      }
      moveTo(vars, profile, e, left / ppu, top / ppu, scr);
      if (c.side === 'left' || c.side === 'right') {
        // a row beside the map hangs from the end nearest it and grows away from it
        const leftSide = c.side === 'left', pt = leftSide ? 'RIGHT' : 'LEFT';
        const bar = cdmBar(vars, profile, e.index);
        bar.set('growDirection', leftSide ? 'LEFT' : 'RIGHT');
        const o = unplace({ point: pt, relPoint: 'CENTER' }, Math.round(left) / ppu, Math.round(top) / ppu, e.w, e.h, scr);
        L.set(db(vars), 'profiles', profile, 'addons', 'EllesmereUICooldownManager', 'cdmBarPositions', e.key,
          new Map([['point', pt], ['relPoint', 'CENTER'], ['x', o.x], ['y', o.y]]));
      }
    }
    return skipped;
  }

  // Puts the Cooldowns and Utility rows side by side above the map and Buffs above them.
  function crownCooldowns(vars, profile, scr, map, marginPx, shape, counts) {
    const ppu = scr.pxPerUnit, skipped = [];
    const get = () => cdmBars(vars, scr, profile, counts);
    for (const k of ['cooldowns', 'utility', 'buffs']) {
      const e = get().find((x) => x.key === k);
      if (e && shape && setShape(vars, profile, e, shape)) skipped.push(e.label);
    }
    const top = map.cy - map.r - marginPx;
    const at = (k, leftFn, bottom) => {
      const e = get().find((x) => x.key === k);
      if (!e || !e.placed) return bottom;
      const w = e.w * ppu, h = e.h * ppu;
      moveTo(vars, profile, e, leftFn(w) / ppu, (bottom - h) / ppu, scr);
      return bottom - h;
    };
    const a = at('cooldowns', (w) => map.cx - 4 - w, top);
    const b = at('utility', () => map.cx + 4, top);
    at('buffs', (w) => map.cx - w / 2, Math.min(a, b) - 8);
    return skipped;
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
    setShape, setField, moveTo, diff, honeycomb, handsPlan, HEX_HEIGHT, questbookMap, layoutBars, hugPlan, crownCooldowns, placeAround, slimFrames, setupAuras, setupResources, setMapSkin,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ElleModel = api;
})(typeof self !== 'undefined' ? self : this);
