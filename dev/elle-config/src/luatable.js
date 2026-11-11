// Reads and writes WoW SavedVariables files (a subset of Lua: assignments of
// literal tables). Tables become Map objects so that number keys and string
// keys stay distinct and the order of entries is kept.
(function (root) {
  'use strict';

  function parse(text) {
    let i = 0;
    const n = text.length;

    function fail(msg) {
      const line = text.slice(0, i).split('\n').length;
      throw new Error('Lua parse error at line ' + line + ': ' + msg);
    }
    function skip() {
      for (;;) {
        const c = text[i];
        if (c === ' ' || c === '\t' || c === '\r' || c === '\n') { i++; continue; }
        if (c === '-' && text[i + 1] === '-') {
          if (text[i + 2] === '[' && text[i + 3] === '[') {
            const e = text.indexOf(']]', i + 4);
            if (e < 0) fail('unterminated comment');
            i = e + 2;
          } else {
            while (i < n && text[i] !== '\n') i++;
          }
          continue;
        }
        return;
      }
    }
    function str() {
      const q = text[i++];
      let out = '';
      for (;;) {
        if (i >= n) fail('unterminated string');
        const c = text[i++];
        if (c === q) return out;
        if (c !== '\\') { out += c; continue; }
        const e = text[i++];
        if (e === 'n') out += '\n';
        else if (e === 'r') out += '\r';
        else if (e === 't') out += '\t';
        else if (e === 'a') out += '\x07';
        else if (e === 'b') out += '\b';
        else if (e === 'f') out += '\f';
        else if (e === 'v') out += '\v';
        else if (e === '\n') out += '\n';
        else if (e >= '0' && e <= '9') {
          let d = e;
          while (d.length < 3 && text[i] >= '0' && text[i] <= '9') d += text[i++];
          out += String.fromCharCode(parseInt(d, 10));
        } else out += e; // \\ \" \'
      }
    }
    function num() {
      const m = /^-?(0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)/.exec(text.slice(i, i + 64));
      if (!m) fail('bad number');
      i += m[0].length;
      return Number(m[0]);
    }
    function word() {
      const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(text.slice(i, i + 128));
      if (!m) fail('unexpected character ' + JSON.stringify(text[i]));
      i += m[0].length;
      return m[0];
    }
    function value() {
      skip();
      const c = text[i];
      if (c === '{') return table();
      if (c === '"' || c === "'") return str();
      if (c === '-' || c === '.' || (c >= '0' && c <= '9')) {
        if (text.startsWith('-inf', i) || text.startsWith('-nan', i)) fail('inf/nan not supported');
        return num();
      }
      const w = word();
      if (w === 'true') return true;
      if (w === 'false') return false;
      if (w === 'nil') return null;
      fail('unexpected word ' + w);
    }
    function table() {
      i++; // {
      const t = new Map();
      let next = 1;
      for (;;) {
        skip();
        if (text[i] === '}') { i++; return t; }
        if (text[i] === '[') {
          i++;
          const k = value();
          skip();
          if (text[i] !== ']') fail('expected ]');
          i++;
          skip();
          if (text[i] !== '=') fail('expected =');
          i++;
          const v = value();
          if (v !== null) t.set(k, v);
        } else if (/[A-Za-z_]/.test(text[i]) && /^[A-Za-z_][A-Za-z0-9_]*\s*=/.test(text.slice(i, i + 128))) {
          const k = word();
          skip();
          i++; // =
          const v = value();
          if (v !== null) t.set(k, v);
        } else {
          const v = value();
          if (v !== null) t.set(next, v);
          next++;
        }
        skip();
        if (text[i] === ',' || text[i] === ';') i++;
      }
    }

    const vars = new Map();
    for (;;) {
      skip();
      if (i >= n) break;
      const name = word();
      skip();
      if (text[i] !== '=') fail('expected = after ' + name);
      i++;
      vars.set(name, value());
    }
    return vars;
  }

  function quote(s) {
    let out = '"';
    for (let k = 0; k < s.length; k++) {
      const c = s[k];
      const code = s.charCodeAt(k);
      if (c === '"') out += '\\"';
      else if (c === '\\') out += '\\\\';
      else if (c === '\n') out += '\\n';
      else if (c === '\r') out += '\\r';
      else if (code < 32 || code === 127) out += '\\' + String(code).padStart(3, '0');
      else out += c;
    }
    return out + '"';
  }

  function numText(v) {
    if (!isFinite(v)) throw new Error('cannot write a non-finite number');
    if (Object.is(v, -0)) return '-0';
    return String(v); // shortest text that reads back as the same double
  }

  function writeValue(v, out) {
    if (v instanceof Map) {
      out.push('{\n');
      for (const [k, val] of v) {
        if (val === null || val === undefined) continue;
        out.push('[', typeof k === 'number' ? numText(k) : typeof k === 'boolean' ? String(k) : quote(k), '] = ');
        writeValue(val, out);
        out.push(',\n');
      }
      out.push('}');
    } else if (typeof v === 'string') out.push(quote(v));
    else if (typeof v === 'number') out.push(numText(v));
    else if (typeof v === 'boolean') out.push(String(v));
    else throw new Error('cannot write value of type ' + typeof v);
  }

  function serialize(vars) {
    const out = [];
    for (const [name, v] of vars) {
      out.push('\n', name, ' = ');
      if (v === null || v === undefined) out.push('nil');
      else writeValue(v, out);
      out.push('\n');
    }
    return out.join('');
  }

  // get(t, 'a', 'b') walks nested Maps; undefined when any step is missing.
  function get(t) {
    for (let k = 1; k < arguments.length; k++) {
      if (!(t instanceof Map)) return undefined;
      t = t.get(arguments[k]);
    }
    return t;
  }

  // set(t, 'a', 'b', value) creates the tables on the way.
  function set(t) {
    const last = arguments.length - 2;
    for (let k = 1; k < last; k++) {
      let nx = t.get(arguments[k]);
      if (!(nx instanceof Map)) { nx = new Map(); t.set(arguments[k], nx); }
      t = nx;
    }
    const v = arguments[last + 1];
    if (v === null || v === undefined) t.delete(arguments[last]);
    else t.set(arguments[last], v);
  }

  function equal(a, b) {
    if (a instanceof Map && b instanceof Map) {
      if (a.size !== b.size) return false;
      for (const [k, v] of a) if (!b.has(k) || !equal(v, b.get(k))) return false;
      return true;
    }
    return Object.is(a, b);
  }

  function toPlain(v) {
    if (!(v instanceof Map)) return v;
    const o = {};
    for (const [k, val] of v) o[String(k)] = toPlain(val);
    return o;
  }

  // One value as Lua source text.
  function lua(v) { const out = []; writeValue(v, out); return out.join(''); }

  const api = { parse, serialize, get, set, equal, toPlain, lua };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.LuaTable = api;
})(typeof self !== 'undefined' ? self : this);
