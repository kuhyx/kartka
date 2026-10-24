/// JS part 2 of the Mangayomi shim: a CSS selector engine over the nodes
/// built by `html_parse_js.dart`. Written for Kartka; no Mangayomi code.
///
/// Supported (sized from every selector in the m2k3a JS manga extensions):
/// type, `*`, `#id`, `.class`, `[a]`, `[a=v]`, `[a~=v]`, `[a|=v]`, `[a^=v]`,
/// `[a$=v]`, `[a*=v]`, combinators ` `, `>`, `+`, `~`, comma groups, a
/// leading combinator (jsoup's `> img`, relative to the element), and
/// `:has()`, `:not()`, `:nth-child()`, `:nth-of-type()`, `:first-child`,
/// `:last-child`, `:only-child`, `:first-of-type`, `:last-of-type`,
/// `:empty`, `:contains()`. Anything else throws a named error.
library;

/// JS source defining `__kmSelectAll(root, css)`.
const String kShimHtmlSelectJs = r'''
function __kmSelError(css, why) {
  return new Error("Mangayomi shim: unsupported selector '" + css + "' (" +
    why + ")");
}

// Parses a selector list into [[{comb, parts}]]; the first step of a
// relative selector has comb ">" | "+" | "~" | " " and a null compound.
function __kmParseSel(css) {
  const s = String(css);
  let i = 0;
  const ws = () => { while (i < s.length && /\s/.test(s[i])) i++; };
  const ident = () => {
    const m = /^(?:\\.|[\w -￿-])+/.exec(s.slice(i));
    if (!m) throw __kmSelError(s, "expected a name at " + i);
    i += m[0].length;
    return m[0].replace(/\\(.)/g, "$1");
  };
  const group = () => {
    let depth = 0;
    const start = i;
    while (i < s.length) {
      const c = s[i];
      if (c === "(") depth++;
      else if (c === ")") { if (depth === 0) break; depth--; }
      else if (c === '"' || c === "'") { i = s.indexOf(c, i + 1); if (i < 0) i = s.length; }
      i++;
    }
    const inner = s.slice(start, i);
    i++;
    return inner;
  };
  const compound = () => {
    const parts = [];
    if (s[i] === "*") { i++; parts.push({ k: "any" }); }
    else if (/[\w-]/.test(s[i] || "")) parts.push({ k: "tag", v: ident().toLowerCase() });
    for (;;) {
      const c = s[i];
      if (c === "#") { i++; parts.push({ k: "id", v: ident() }); }
      else if (c === ".") { i++; parts.push({ k: "cls", v: ident() }); }
      else if (c === "[") {
        i++; ws();
        const name = ident().toLowerCase(); ws();
        let op = null; let val = null;
        const m = /^([~|^$*]?=)/.exec(s.slice(i));
        if (m) {
          op = m[1]; i += op.length; ws();
          const q = s[i];
          if (q === '"' || q === "'") {
            const end = s.indexOf(q, i + 1);
            if (end < 0) throw __kmSelError(s, "unterminated string");
            val = s.slice(i + 1, end); i = end + 1;
          } else {
            const mv = /^[^\]\s]+/.exec(s.slice(i));
            val = mv ? mv[0] : ""; i += val.length;
          }
          ws();
          if (/^[iI]\s*\]/.test(s.slice(i))) { i++; ws(); }
        }
        if (s[i] !== "]") throw __kmSelError(s, "expected ]");
        i++;
        parts.push({ k: "attr", name: name, op: op, v: val });
      } else if (c === ":") {
        i++;
        const name = ident().toLowerCase();
        let arg = null;
        if (s[i] === "(") { i++; arg = group(); }
        parts.push(__kmPseudo(s, name, arg));
      } else break;
    }
    return parts;
  };
  const groups = [];
  let steps = [];
  ws();
  let comb = null;
  if (/[>+~]/.test(s[i] || "")) { comb = s[i]; i++; ws(); steps.push({ comb: comb, parts: null }); }
  while (i < s.length) {
    const parts = compound();
    if (!parts.length) throw __kmSelError(s, "unexpected '" + s[i] + "' at " + i);
    steps.push({ comb: comb || " ", parts: parts });
    const before = i;
    ws();
    comb = null;
    if (i >= s.length) break;
    if (s[i] === ",") {
      i++; ws(); groups.push(steps); steps = [];
      if (/[>+~]/.test(s[i] || "")) { steps.push({ comb: s[i], parts: null }); comb = s[i]; i++; ws(); }
    } else if (/[>+~]/.test(s[i])) { comb = s[i]; i++; ws(); }
    else if (i > before) comb = " ";
    else throw __kmSelError(s, "unexpected '" + s[i] + "' at " + i);
  }
  if (steps.length) groups.push(steps);
  if (!groups.length) throw __kmSelError(s, "empty selector");
  return groups;
}

function __kmPseudo(s, name, arg) {
  const simple = ["first-child", "last-child", "only-child", "first-of-type",
    "last-of-type", "empty"];
  if (simple.indexOf(name) >= 0) return { k: name };
  if (name === "has" || name === "not") return { k: name, sel: __kmParseSel(arg) };
  if (name === "contains") return { k: name, v: arg.trim().replace(/^["']|["']$/g, "").toLowerCase() };
  if (name === "nth-child" || name === "nth-of-type") {
    const a = arg.trim().toLowerCase();
    let m;
    if (a === "odd") return { k: name, a: 2, b: 1 };
    if (a === "even") return { k: name, a: 2, b: 0 };
    if ((m = /^([+-]?\d*)n\s*(?:([+-])\s*(\d+))?$/.exec(a))) {
      const step = m[1] === "" || m[1] === "+" ? 1 : m[1] === "-" ? -1 : parseInt(m[1], 10);
      const off = m[2] ? parseInt(m[3], 10) * (m[2] === "-" ? -1 : 1) : 0;
      return { k: name, a: step, b: off };
    }
    if (/^[+-]?\d+$/.test(a)) return { k: name, a: 0, b: parseInt(a, 10) };
  }
  throw __kmSelError(s, ":" + name + (arg === null ? "" : "(" + arg + ")"));
}

function __kmAttr(el, name) {
  for (const a of el.attrs) if (a[0] === name) return a[1];
  return null;
}

function __kmSiblings(el) {
  return el.up ? el.up.kids.filter((k) => k.t === 1) : [el];
}

function __kmNth(pos, a, b) {
  if (a === 0) return pos === b;
  return (pos - b) / a >= 0 && (pos - b) % a === 0;
}

function __kmMatchPart(el, p, scope) {
  switch (p.k) {
    case "any": return true;
    case "tag": return el.tag === p.v;
    case "id": return __kmAttr(el, "id") === p.v;
    case "cls": return (" " + (__kmAttr(el, "class") || "") + " ")
      .replace(/\s+/g, " ").indexOf(" " + p.v + " ") >= 0;
    case "attr": {
      const v = __kmAttr(el, p.name);
      if (v === null) return false;
      switch (p.op) {
        case null: return true;
        case "=": return v === p.v;
        case "~=": return v.split(/\s+/).indexOf(p.v) >= 0;
        case "|=": return v === p.v || v.startsWith(p.v + "-");
        case "^=": return p.v !== "" && v.startsWith(p.v);
        case "$=": return p.v !== "" && v.endsWith(p.v);
        default: return p.v !== "" && v.indexOf(p.v) >= 0;
      }
    }
    case "has": return __kmSelectAll(el, p.sel).length > 0;
    case "not": return !p.sel.some((g) => __kmMatchSteps(el, g, g.length - 1, scope));
    case "contains": return __kmText(el).toLowerCase().indexOf(p.v) >= 0;
    case "empty": return el.kids.every((k) => k.t !== 1 && !(k.t === 3 && k.text));
  }
  const sibs = __kmSiblings(el);
  const typed = p.k.indexOf("type") >= 0 ? sibs.filter((x) => x.tag === el.tag) : sibs;
  const pos = typed.indexOf(el) + 1;
  if (p.k === "first-child" || p.k === "first-of-type") return pos === 1;
  if (p.k === "last-child" || p.k === "last-of-type") return pos === typed.length;
  if (p.k === "only-child") return typed.length === 1;
  return __kmNth(pos, p.a, p.b);
}

// Does `el` match steps[0..idx], where steps[idx] must match `el` itself?
function __kmMatchSteps(el, steps, idx, scope) {
  const step = steps[idx];
  if (step.parts === null) return el === scope;
  if (el.t !== 1 || !step.parts.every((p) => __kmMatchPart(el, p, scope))) return false;
  if (idx === 0) return true;
  const comb = step.comb;
  if (comb === ">") return !!el.up && __kmMatchSteps(el.up, steps, idx - 1, scope);
  if (comb === " ") {
    for (let up = el.up; up; up = up.up) {
      if (__kmMatchSteps(up, steps, idx - 1, scope)) return true;
    }
    return false;
  }
  const sibs = __kmSiblings(el);
  const at = sibs.indexOf(el);
  if (comb === "+") return at > 0 && __kmMatchSteps(sibs[at - 1], steps, idx - 1, scope);
  for (let k = at - 1; k >= 0; k--) {
    if (__kmMatchSteps(sibs[k], steps, idx - 1, scope)) return true;
  }
  return false;
}

// Every element under `root` (not root itself) matching `css` or a parsed
// selector list, in document order. Sibling-relative leading combinators
// (`+ x`, `~ x`) are matched against root's later siblings.
function __kmSelectAll(root, css) {
  const groups = typeof css === "string" ? __kmParseSel(css) : css;
  const out = [];
  const visit = (node) => {
    for (const kid of node.kids) {
      if (kid.t !== 1) continue;
      if (groups.some((g) => __kmMatchSteps(kid, g, g.length - 1, root))) out.push(kid);
      visit(kid);
    }
  };
  visit(root);
  if (root.t === 1 && groups.some((g) => g[0].parts === null && g[0].comb !== ">" && g[0].comb !== " ")) {
    for (const sib of __kmSiblings(root)) {
      if (sib !== root && groups.some((g) => __kmMatchSteps(sib, g, g.length - 1, root))) out.push(sib);
    }
  }
  return out;
}
''';
