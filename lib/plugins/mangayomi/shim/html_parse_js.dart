/// JS part 1 of the Mangayomi shim: a small forgiving HTML parser.
///
/// Mangayomi's `Document`/`Element` API is synchronous, while Kartka's
/// `kartka.html.select` is a Promise (it crosses the isolate/worker boundary),
/// so the shim parses HTML inside the plugin sandbox instead. Written for
/// Kartka from the HTML spec's tokenizer rules; no Mangayomi code is used.
///
/// Nodes: `{t: 1, tag, attrs: [[name, value]], kids, up}` for elements,
/// `{t: 3, text, up}` for text, `{t: 9, kids}` for the document. Comments,
/// doctypes and processing instructions are dropped.
library;

/// JS source defining `__kmParseHtml(html)` and `__kmSerialize(node, outer)`.
const String kShimHtmlParseJs = r'''
const __kmVoid = new Set(["area", "base", "br", "col", "embed", "hr", "img",
  "input", "link", "meta", "param", "source", "track", "wbr"]);
const __kmRawText = new Set(["script", "style", "xmp", "iframe", "noembed",
  "noframes"]);
const __kmRcData = new Set(["textarea", "title"]);
// Opening one of these closes an open <p> (HTML "close a p element").
const __kmClosesP = new Set(["address", "article", "aside", "blockquote",
  "details", "div", "dl", "fieldset", "figcaption", "figure", "footer",
  "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "main", "nav",
  "ol", "p", "pre", "section", "table", "ul"]);
const __kmEntities = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
  copy: "©", reg: "®", trade: "™", hellip: "…",
  mdash: "—", ndash: "–", lsquo: "‘", rsquo: "’",
  ldquo: "“", rdquo: "”", laquo: "«", raquo: "»",
  middot: "·", bull: "•", times: "×", deg: "°",
};

function __kmDecode(s) {
  if (s.indexOf("&") < 0) return s;
  return s.replace(/&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);?/g,
    (m, body) => {
      if (body[0] === "#") {
        const hex = body[1] === "x" || body[1] === "X";
        const code = parseInt(body.slice(hex ? 2 : 1), hex ? 16 : 10);
        return code > 0 && code < 0x110000 ? String.fromCodePoint(code) : m;
      }
      const named = __kmEntities[body];
      return named === undefined ? m : named;
    });
}

function __kmEl(tag, attrs, up) {
  return { t: 1, tag: tag, attrs: attrs, kids: [], up: up };
}

// Reads the attributes of a start tag beginning at `i`; returns the index
// just past `>` plus whether the tag was written self-closing.
function __kmReadAttrs(src, i, attrs) {
  const n = src.length;
  let selfClose = false;
  while (i < n) {
    const c = src[i];
    if (c === ">") return { i: i + 1, selfClose: selfClose };
    if (c === "/") { selfClose = true; i++; continue; }
    if (/\s/.test(c)) { i++; continue; }
    selfClose = false;
    let j = i;
    while (j < n && !/[\s=>]/.test(src[j]) && !(src[j] === "/" && j > i)) j++;
    const name = src.slice(i, j).toLowerCase();
    i = j;
    while (i < n && /\s/.test(src[i])) i++;
    let value = "";
    if (src[i] === "=") {
      i++;
      while (i < n && /\s/.test(src[i])) i++;
      const q = src[i];
      if (q === '"' || q === "'") {
        const end = src.indexOf(q, i + 1);
        const stop = end < 0 ? n : end;
        value = src.slice(i + 1, stop);
        i = stop + 1;
      } else {
        let k = i;
        while (k < n && !/[\s>]/.test(src[k])) k++;
        value = src.slice(i, k);
        i = k;
      }
    }
    if (name && !attrs.some((a) => a[0] === name)) {
      attrs.push([name, __kmDecode(value)]);
    }
  }
  return { i: n, selfClose: selfClose };
}

// Implied end tags: close what a new `tag` cannot sit inside.
function __kmImplyClose(stack, tag) {
  const has = (names, stopAt) => {
    for (let k = stack.length - 1; k > 0; k--) {
      if (names.indexOf(stack[k].tag) >= 0) return k;
      if (stopAt.indexOf(stack[k].tag) >= 0) return -1;
    }
    return -1;
  };
  const popTo = (k) => { if (k > 0) stack.length = k; };
  if (__kmClosesP.has(tag)) popTo(has(["p"], ["button", "table"]));
  if (tag === "li") popTo(has(["li"], ["ul", "ol"]));
  if (tag === "dt" || tag === "dd") popTo(has(["dt", "dd"], ["dl"]));
  if (tag === "option") popTo(has(["option"], ["select", "datalist"]));
  if (tag === "td" || tag === "th") popTo(has(["td", "th"], ["tr", "table"]));
  if (tag === "tr") popTo(has(["tr"], ["table"]));
  if (tag === "tbody" || tag === "thead" || tag === "tfoot") {
    popTo(has(["tbody", "thead", "tfoot"], ["table"]));
  }
}

function __kmParseHtml(html) {
  const src = String(html == null ? "" : html);
  const doc = { t: 9, kids: [], up: null };
  const stack = [doc];
  const top = () => stack[stack.length - 1];
  const addText = (text) => {
    if (!text) return;
    const parent = top();
    const last = parent.kids[parent.kids.length - 1];
    if (last && last.t === 3) last.text += text;
    else parent.kids.push({ t: 3, text: text, up: parent });
  };
  const n = src.length;
  let i = 0;
  while (i < n) {
    const lt = src.indexOf("<", i);
    if (lt < 0) { addText(__kmDecode(src.slice(i))); break; }
    if (lt > i) addText(__kmDecode(src.slice(i, lt)));
    i = lt;
    if (src.startsWith("<!--", i)) {
      const end = src.indexOf("-->", i + 4);
      i = end < 0 ? n : end + 3;
    } else if (src[i + 1] === "!" || src[i + 1] === "?") {
      const end = src.indexOf(">", i);
      i = end < 0 ? n : end + 1;
    } else if (src[i + 1] === "/" && /[a-zA-Z]/.test(src[i + 2] || "")) {
      const end = src.indexOf(">", i);
      const name = src.slice(i + 2, end < 0 ? n : end).trim().split(/[\s/]/)[0]
        .toLowerCase();
      i = end < 0 ? n : end + 1;
      for (let k = stack.length - 1; k > 0; k--) {
        if (stack[k].tag === name) { stack.length = k; break; }
      }
    } else if (/[a-zA-Z]/.test(src[i + 1] || "")) {
      let j = i + 1;
      while (j < n && !/[\s/>]/.test(src[j])) j++;
      const tag = src.slice(i + 1, j).toLowerCase();
      const attrs = [];
      const r = __kmReadAttrs(src, j, attrs);
      i = r.i;
      __kmImplyClose(stack, tag);
      const el = __kmEl(tag, attrs, top());
      top().kids.push(el);
      if (__kmRawText.has(tag) || __kmRcData.has(tag)) {
        const close = src.toLowerCase().indexOf("</" + tag, i);
        const stop = close < 0 ? n : close;
        const body = src.slice(i, stop);
        if (body) {
          const text = __kmRcData.has(tag) ? __kmDecode(body) : body;
          el.kids.push({ t: 3, text: text, up: el });
        }
        const gt = close < 0 ? n : src.indexOf(">", close);
        i = gt < 0 ? n : gt + 1;
      } else if (!__kmVoid.has(tag) && !r.selfClose) {
        stack.push(el);
      }
    } else {
      addText("<");
      i++;
    }
  }
  return doc;
}

function __kmEscape(s, attr) {
  let out = s.replace(/&/g, "&amp;").replace(/ /g, "&nbsp;");
  if (attr) return out.replace(/"/g, "&quot;");
  return out.replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function __kmSerialize(node, outer) {
  if (node.t === 3) {
    const raw = node.up && node.up.t === 1 && __kmRawText.has(node.up.tag);
    return raw ? node.text : __kmEscape(node.text, false);
  }
  let inner = "";
  for (const kid of node.kids) inner += __kmSerialize(kid, true);
  if (!outer || node.t !== 1) return inner;
  let open = "<" + node.tag;
  for (const a of node.attrs) open += " " + a[0] + '="' + __kmEscape(a[1], true) + '"';
  open += ">";
  return __kmVoid.has(node.tag) ? open : open + inner + "</" + node.tag + ">";
}

function __kmText(node) {
  if (node.t === 3) return node.text;
  let out = "";
  for (const kid of node.kids) out += __kmText(kid);
  return out;
}
''';
