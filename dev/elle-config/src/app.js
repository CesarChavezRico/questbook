// The page: loads a settings file, draws it, edits it, saves it.
(function () {
  'use strict';
  const L = self.LuaTable, M = self.ElleModel;
  const $ = (id) => document.getElementById(id);
  const SVG = 'http://www.w3.org/2000/svg';

  const state = {
    vars: null, original: null, fileName: 'EllesmereUI.lua', profile: null,
    physW: 3440, physH: 1440, selected: null, showHidden: false, previewCounts: {}, els: [], scr: null,
  };

  function el(tag, attrs, parent) {
    const e = document.createElementNS(SVG, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  function h(tag, props, parent) {
    const e = document.createElement(tag);
    Object.assign(e, props || {});
    if (parent) parent.appendChild(e);
    return e;
  }

  // Outline of one button or icon, in a box x,y,w,h.
  function shapePath(shape, x, y, w, hh) {
    const cx = x + w / 2, cy = y + hh / 2, r = Math.min(w, hh) / 2;
    const pts = (a) => 'M' + a.map((p) => p[0].toFixed(2) + ' ' + p[1].toFixed(2)).join('L') + 'Z';
    if (shape === 'circle') return 'M' + (cx - r) + ' ' + cy + 'a' + r + ' ' + r + ' 0 1 0 ' + 2 * r + ' 0a' + r + ' ' + r + ' 0 1 0 ' + -2 * r + ' 0Z';
    if (shape === 'hexagon') {
      const q = w * 0.25, v = hh * (1 - M.HEX_HEIGHT) / 2;   // the art leaves a margin above and below
      return pts([[x + q, y + v], [x + w - q, y + v], [x + w, cy], [x + w - q, y + hh - v], [x + q, y + hh - v], [x, cy]]);
    }
    if (shape === 'diamond') return pts([[cx, y], [x + w, cy], [cx, y + hh], [x, cy]]);
    if (shape === 'shield') {
      return 'M' + x + ' ' + (y + hh * 0.12) + 'Q' + cx + ' ' + (y - hh * 0.06) + ' ' + (x + w) + ' ' + (y + hh * 0.12) +
        'L' + (x + w) + ' ' + (y + hh * 0.5) + 'Q' + (x + w) + ' ' + (y + hh * 0.82) + ' ' + cx + ' ' + (y + hh) +
        'Q' + x + ' ' + (y + hh * 0.82) + ' ' + x + ' ' + (y + hh * 0.5) + 'Z';
    }
    if (shape === 'portrait') {
      return 'M' + cx + ' ' + y + 'A' + r + ' ' + r + ' 0 0 1 ' + (x + w) + ' ' + cy + 'L' + (x + w) + ' ' + (y + hh) +
        'L' + cx + ' ' + (y + hh) + 'A' + r + ' ' + r + ' 0 0 1 ' + x + ' ' + cy + 'A' + r + ' ' + r + ' 0 0 1 ' + cx + ' ' + y + 'Z';
    }
    if (shape === 'csquare') {
      const c = Math.min(w, hh) * 0.22;
      return 'M' + (x + c) + ' ' + y + 'H' + (x + w - c) + 'Q' + (x + w) + ' ' + y + ' ' + (x + w) + ' ' + (y + c) + 'V' + (y + hh - c) +
        'Q' + (x + w) + ' ' + (y + hh) + ' ' + (x + w - c) + ' ' + (y + hh) + 'H' + (x + c) + 'Q' + x + ' ' + (y + hh) + ' ' + x + ' ' + (y + hh - c) +
        'V' + (y + c) + 'Q' + x + ' ' + y + ' ' + (x + c) + ' ' + y + 'Z';
    }
    return pts([[x, y], [x + w, y], [x + w, y + hh], [x, y + hh]]);
  }

  function recompute() {
    state.scr = M.screen(state.vars, state.physW, state.physH);
    state.els = M.elements(state.vars, state.scr, state.profile, state.previewCounts);
  }
  function selectedEl() { return state.els.find((e) => e.id === state.selected) || null; }

  function draw() {
    const svg = $('stage');
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    const scr = state.scr;
    svg.setAttribute('viewBox', '0 0 ' + scr.uiW + ' ' + scr.uiH);
    svg.style.aspectRatio = scr.uiW + ' / ' + scr.uiH;
    el('rect', { x: 0, y: 0, width: scr.uiW, height: scr.uiH, class: 'screen' }, svg);
    el('line', { x1: scr.uiW / 2, y1: 0, x2: scr.uiW / 2, y2: scr.uiH, class: 'guide' }, svg);
    el('line', { x1: 0, y1: scr.uiH / 2, x2: scr.uiW, y2: scr.uiH / 2, class: 'guide' }, svg);

    for (const e of state.els) {
      if (!e.placed) continue;
      if (e.hidden && !state.showHidden && e.id !== state.selected) continue;
      const g = el('g', { transform: 'translate(' + e.left + ' ' + e.top + ')', class: 'el ' + e.kind + (e.hidden ? ' hiddenEl' : '') + (e.id === state.selected ? ' sel' : ''), 'data-id': e.id }, svg);
      el('rect', { x: -2, y: -2, width: e.w + 4, height: e.h + 4, class: 'frame' }, g);
      if (!e.cells.length) el('rect', { x: 0, y: 0, width: e.w, height: e.h, class: 'cell' }, g);
      for (const c of e.cells) {
        const sw = Math.max(e.borderPx, 0) * scr.onePx;
        el('path', { d: shapePath(e.shape, c.x, c.y, c.w, c.h), class: 'cell', 'stroke-width': sw }, g);
        if (c.label && c.w >= 20) {
          const t = el('text', { x: c.x + c.w / 2, y: c.y + c.h / 2, class: 'num', 'font-size': Math.min(c.w, c.h) * 0.36 }, g);
          t.textContent = c.label;
        }
      }
      const lab = el('text', { x: 0, y: -6, class: 'label', 'font-size': 13 }, g);
      lab.textContent = e.label + (e.hidden ? ' (hidden in game)' : '');
    }
    svg.querySelectorAll('g.el').forEach((g) => g.addEventListener('pointerdown', startDrag));
  }

  // ---- dragging ------------------------------------------------------------
  let drag = null;
  function toUi(evt) {
    const svg = $('stage'), r = svg.getBoundingClientRect();
    return { x: (evt.clientX - r.left) * state.scr.uiW / r.width, y: (evt.clientY - r.top) * state.scr.uiH / r.height };
  }
  function startDrag(evt) {
    const id = evt.currentTarget.getAttribute('data-id');
    state.selected = id;
    const e = selectedEl();
    if (e && (e.kind === 'actionbar' || e.kind === 'cdm')) {
      const p = toUi(evt);
      drag = { id, dx: p.x - e.left, dy: p.y - e.top, moved: false };
      evt.currentTarget.setPointerCapture(evt.pointerId);
    }
    render();
    evt.preventDefault();
  }
  window.addEventListener('pointermove', (evt) => {
    if (!drag) return;
    const e = selectedEl(); if (!e) return;
    const p = toUi(evt);
    drag.moved = true;
    M.moveTo(state.vars, state.profile, e, p.x - drag.dx, p.y - drag.dy, state.scr);
    recompute(); draw(); renderProps(true);
  });
  window.addEventListener('pointerup', () => { if (drag) { const moved = drag.moved; drag = null; if (moved) render(); } });
  window.addEventListener('keydown', (evt) => {
    const e = selectedEl();
    if (!e || !e.placed || /INPUT|SELECT|TEXTAREA/.test(document.activeElement.tagName)) return;
    const step = (evt.shiftKey ? 10 : 1) * state.scr.onePx;
    const d = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }[evt.key];
    if (!d) return;
    if (!M.moveTo(state.vars, state.profile, e, e.left + d[0], e.top + d[1], state.scr)) { evt.preventDefault(); render(); }
  });

  // ---- side panels ---------------------------------------------------------
  function renderList() {
    const box = $('list'); box.textContent = '';
    for (const e of state.els) {
      const row = h('button', { className: 'row' + (e.id === state.selected ? ' on' : '') + (e.hidden ? ' dim' : ''), type: 'button' }, box);
      row.textContent = e.label + (e.hidden ? ' · hidden' : '') + (!e.placed ? ' · not drawn' : '');
      row.onclick = () => { state.selected = e.id; render(); };
    }
  }

  function field(parent, label, input) {
    const w = h('label', { className: 'field' }, parent);
    h('span', { textContent: label }, w);
    w.appendChild(input);
    return input;
  }
  function numInput(value, step, onChange) {
    const i = h('input', { type: 'number', value: String(Math.round(value * 1000) / 1000), step: String(step) });
    i.onchange = () => { const v = Number(i.value); if (isFinite(v)) onChange(v); };
    return i;
  }
  function select(options, value, onChange) {
    const s = h('select');
    for (const [v, t] of options) h('option', { value: v, textContent: t, selected: v === value }, s);
    s.onchange = () => onChange(s.value);
    return s;
  }
  function check(value, onChange) {
    const c = h('input', { type: 'checkbox', checked: !!value });
    c.onchange = () => onChange(c.checked);
    return c;
  }
  function apply(err) { if (err) alert(err); render(); }

  function renderProps(positionOnly) {
    const box = $('props');
    const e = selectedEl();
    if (positionOnly && e) {
      const px = $('posx'), py = $('posy');
      if (px && py) { px.value = Math.round(e.left * state.scr.pxPerUnit); py.value = Math.round(e.top * state.scr.pxPerUnit); }
      return;
    }
    box.textContent = '';
    if (!e) { h('p', { className: 'hint', textContent: 'Click a bar in the drawing or in the list.' }, box); return; }
    h('h2', { textContent: e.label }, box);
    const editable = e.kind === 'actionbar' || e.kind === 'cdm';
    const ppu = state.scr.pxPerUnit;
    const set = (f) => (v) => apply(M.setField(state.vars, state.profile, e, f, v));

    if (e.placed) {
      const px = field(box, 'Left edge (screen pixels)', numInput(e.left * ppu, 1, (v) => apply(M.moveTo(state.vars, state.profile, e, v / ppu, e.top, state.scr))));
      const py = field(box, 'Top edge (screen pixels)', numInput(e.top * ppu, 1, (v) => apply(M.moveTo(state.vars, state.profile, e, e.left, v / ppu, state.scr))));
      px.id = 'posx'; py.id = 'posy'; px.disabled = py.disabled = !editable;
      h('p', { className: 'hint', textContent: 'Size on screen: ' + Math.round(e.w * ppu) + ' × ' + Math.round(e.h * ppu) + ' pixels.' + (editable ? ' Drag it, or use the arrow keys (Shift for 10 pixels).' : '') }, box);
    }
    if (editable) {
      const s = e.settings;
      field(box, 'Hidden in game', check(e.hidden, set('hidden')));
      field(box, 'Shape', select(M.SHAPES.map((v) => [v, M.SHAPE_LABELS[v]]), s.shape, (v) => apply(M.setShape(state.vars, state.profile, e, v))));
      const all = h('button', { type: 'button', className: 'small', textContent: 'Use this shape on all ' + (e.kind === 'actionbar' ? 'action bars' : 'cooldown bars') }, box);
      all.onclick = () => {
        const errs = [];
        for (const o of state.els) if (o.kind === e.kind && o.id !== e.id) { const r = M.setShape(state.vars, state.profile, o, s.shape); if (r) errs.push(o.label + ': ' + r); }
        apply(errs.join('\n'));
      };
      field(box, 'Border', select(M.THICKNESS.map((v) => [v, v[0].toUpperCase() + v.slice(1)]), s.borderThickness, set('borderThickness')));
      if (e.kind === 'actionbar') {
        field(box, 'Buttons', numInput(s.numIcons, 1, set('numIcons')));
        field(box, s.vertical ? 'Columns' : 'Rows', numInput(s.numRows, 1, set('numRows')));
        field(box, 'Vertical', check(s.vertical, set('vertical')));
        field(box, 'Button width (pixels)', numInput(s.buttonWidth * ppu, 1, (v) => set('buttonWidth')(v / ppu)));
        field(box, 'Button height (pixels)', numInput(s.buttonHeight * ppu, 1, (v) => set('buttonHeight')(v / ppu)));
        field(box, 'Gap between buttons (pixels)', numInput(s.buttonPadding * ppu, 1, (v) => set('buttonPadding')(v / ppu)));
      } else {
        field(box, 'Icon size (pixels)', numInput(s.iconSize * ppu, 1, (v) => set('iconSize')(v / ppu)));
        field(box, 'Gap between icons (pixels)', numInput(s.spacing * ppu, 1, (v) => set('spacing')(v / ppu)));
        field(box, 'Rows', numInput(s.numRows, 1, set('numRows')));
        field(box, 'Vertical', check(s.vertical, set('vertical')));
        field(box, 'Icons shown in this preview (not saved)', numInput(e.previewCount, 1, (v) => { state.previewCounts[e.key] = Math.max(1, Math.round(v)); render(); }));
      }
    }
    for (const n of e.notes) h('p', { className: 'note', textContent: n }, box);
  }

  function renderChanges() {
    const box = $('changes'); box.textContent = '';
    const d = M.diff(state.original.get('EllesmereUIDB'), state.vars.get('EllesmereUIDB'));
    $('save').disabled = d.length === 0;
    $('count').textContent = d.length ? d.length + ' value' + (d.length === 1 ? '' : 's') + ' changed' : 'No changes yet';
    const strip = 'profiles.' + state.profile + '.addons.';
    for (const c of d) {
      const row = h('div', { className: 'chg' }, box);
      const fmt = (v) => (typeof v === 'number' ? String(Math.round(v * 1000) / 1000) : String(v));
      row.textContent = c.path.replace(strip, '').replace('EllesmereUI', '') + ': ' + fmt(c.from) + ' → ' + fmt(c.to);
    }
  }

  function render() {
    recompute(); draw(); renderList(); renderProps(); renderChanges();
    const s = state.scr;
    $('info').textContent = 'Profile "' + state.profile + '" · UI scale ' + (Math.round(s.scale * 1000) / 1000) + (s.scaleFromFile ? '' : ' (not in file, assumed)') +
      ' · one UI unit = ' + (Math.round(s.pxPerUnit * 1000) / 1000) + ' pixels';
  }

  // ---- honeycomb preset -----------------------------------------------------
  $('hcApply').onclick = () => {
    if (!state.vars) return;
    recompute();
    const ppu = state.scr.pxPerUnit;
    const plan = M.handsPlan(state.vars, state.scr, state.profile, {
      size: Number($('hcSize').value) / ppu, gap: Number($('hcGap').value) / ppu, flip: $('hcFlip').checked,
    });
    const err = M.honeycomb(state.vars, state.profile, state.scr, plan);
    const box = $('hcSeats'); box.textContent = '';
    for (const b of plan.blocks) for (const c of b.cells) h('div', { className: 'chg', textContent: M.AB_BARS.find((x) => x.key === c.bar).label + ': ' + c.seat }, box);
    if (err) alert(err);
    render();
  };

  // ---- file in, file out ---------------------------------------------------
  function load(text, name) {
    let vars;
    try { vars = L.parse(text); M.db(vars); } catch (err) { alert(err.message); return; }
    // Safety: writing the file back must give the same data.
    if (!L.equal(vars, L.parse(L.serialize(vars)))) { alert('This file does not survive a read and write unchanged, so editing it here is not safe. Nothing was loaded.'); return; }
    state.vars = vars; state.original = L.parse(text); state.fileName = name || 'EllesmereUI.lua';
    state.profile = M.profileName(vars); state.selected = null; state.previewCounts = {};
    document.body.classList.add('loaded');
    recompute();
    const mainBar = state.els.find((e) => e.id === 'ab:MainBar');
    if (mainBar) $('hcSize').value = Math.round(mainBar.settings.buttonWidth * state.scr.pxPerUnit);
    render();
  }
  $('file').onchange = (evt) => {
    const f = evt.target.files[0]; if (!f) return;
    const r = new FileReader();
    r.onload = () => load(String(r.result), f.name);
    r.readAsText(f);
  };
  $('save').onclick = () => {
    const blob = new Blob([L.serialize(state.vars)], { type: 'text/plain' });
    const a = h('a', { href: URL.createObjectURL(blob), download: state.fileName }, document.body);
    a.click(); a.remove();
  };
  $('reset').onclick = () => { if (state.original && confirm('Drop every change and go back to the loaded file?')) load(L.serialize(state.original), state.fileName); };
  $('showHidden').onchange = (evt) => { state.showHidden = evt.target.checked; render(); };
  for (const id of ['physW', 'physH']) {
    $(id).onchange = () => { const v = Number($(id).value); if (v >= 320) { state[id] = v; if (state.vars) render(); } };
  }
  $('shot').onchange = (evt) => {
    const f = evt.target.files[0]; if (!f) return;
    $('under').src = URL.createObjectURL(f); $('under').style.display = 'block';
  };
  $('shotAlpha').oninput = (evt) => { $('under').style.opacity = evt.target.value; };
})();
