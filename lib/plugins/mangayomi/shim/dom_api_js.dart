/// JS part 3 of the Mangayomi shim: the `Document` / `Element` classes that
/// Mangayomi extensions call, implemented over the shim's own parser and
/// selector engine. Written for Kartka from Mangayomi's public extension API;
/// no Mangayomi code is used.
///
/// Mangayomi semantics kept on purpose because extensions depend on them:
/// * `selectFirst` never returns null: a miss yields an empty `Element` whose
///   strings are `""` and lists `[]` (`doc.selectFirst("x").text.length`).
/// * `attr()` of a missing attribute is `""`.
/// * `text` is the raw text content (not whitespace-normalised).
/// * `getSrc` / `getHref` / `getImg` / `getDataSrc` return the first attribute
///   in the element's subtree (itself first) whose name ends in `src` /
///   `href` / `img` / `data-src`. Values are entity-decoded.
/// * `xpath` is not supported and throws a named error.
library;

/// JS source defining `Document` and `Element`.
const String kShimDomApiJs = r'''
function __kmFirstAttrEnding(node, suffix) {
  if (!node) return "";
  const stack = [node];
  while (stack.length) {
    const n = stack.shift();
    if (n.t !== 1) continue;
    for (const a of n.attrs) if (a[0].endsWith(suffix)) return a[1];
    stack.unshift(...n.kids);
  }
  return "";
}

function __kmXpath() {
  throw new Error("Mangayomi shim: xpath is not supported");
}

function __kmWrapAll(nodes) {
  return nodes.map((n) => new Element(n));
}

function __kmDescendants(root, test) {
  const out = [];
  const visit = (node) => {
    for (const kid of node.kids) {
      if (kid.t !== 1) continue;
      if (test(kid)) out.push(kid);
      visit(kid);
    }
  };
  if (root) visit(root);
  return out;
}

function __kmHasClass(el, name) {
  return (" " + (__kmAttr(el, "class") || "") + " ").replace(/\s+/g, " ")
    .indexOf(" " + name + " ") >= 0;
}

class Element {
  constructor(node) {
    this._n = node && node.t === 1 ? node : null;
  }
  get text() { return this._n ? __kmText(this._n) : ""; }
  get outerHtml() { return this._n ? __kmSerialize(this._n, true) : ""; }
  get innerHtml() { return this._n ? __kmSerialize(this._n, false) : ""; }
  get className() { return this._n ? __kmAttr(this._n, "class") || "" : ""; }
  get localName() { return this._n ? this._n.tag : ""; }
  get namespaceUri() { return this._n ? "http://www.w3.org/1999/xhtml" : ""; }
  get getSrc() { return __kmFirstAttrEnding(this._n, "src"); }
  get getImg() { return __kmFirstAttrEnding(this._n, "img"); }
  get getHref() { return __kmFirstAttrEnding(this._n, "href"); }
  get getDataSrc() { return __kmFirstAttrEnding(this._n, "data-src"); }
  _sibling(delta) {
    if (!this._n || !this._n.up) return new Element(null);
    const sibs = __kmSiblings(this._n);
    return new Element(sibs[sibs.indexOf(this._n) + delta] || null);
  }
  get nextElementSibling() { return this._sibling(1); }
  get previousElementSibling() { return this._sibling(-1); }
  get parent() {
    return new Element(this._n && this._n.up && this._n.up.t === 1 ? this._n.up : null);
  }
  get children() {
    return this._n ? __kmWrapAll(this._n.kids.filter((k) => k.t === 1)) : [];
  }
  getElementsByTagName(name) {
    const tag = String(name).toLowerCase();
    return __kmWrapAll(__kmDescendants(this._n, (e) => e.tag === tag));
  }
  getElementsByClassName(name) {
    return __kmWrapAll(__kmDescendants(this._n, (e) => __kmHasClass(e, name)));
  }
  attr(name) {
    if (!this._n) return "";
    const v = __kmAttr(this._n, String(name).toLowerCase());
    return v === null ? "" : v;
  }
  hasAttr(name) {
    return !!this._n && __kmAttr(this._n, String(name).toLowerCase()) !== null;
  }
  select(css) { return this._n ? __kmWrapAll(__kmSelectAll(this._n, css)) : []; }
  selectFirst(css) {
    return new Element(this._n ? __kmSelectAll(this._n, css)[0] || null : null);
  }
  xpath() { return __kmXpath(); }
  xpathFirst() { return __kmXpath(); }
}

class Document {
  constructor(html) {
    this.html = html;
    this._root = __kmParseHtml(html);
  }
  _find(tag) {
    return __kmDescendants(this._root, (e) => e.tag === tag)[0] || null;
  }
  get documentElement() {
    return new Element(this._root.kids.find((k) => k.t === 1) || null);
  }
  get body() { return new Element(this._find("body")); }
  get head() { return new Element(this._find("head")); }
  get parent() { return new Element(null); }
  get text() { return __kmText(this._root); }
  get outerHtml() { return __kmSerialize(this._root, true); }
  get children() {
    return __kmWrapAll(this._root.kids.filter((k) => k.t === 1));
  }
  select(css) { return __kmWrapAll(__kmSelectAll(this._root, css)); }
  selectFirst(css) { return new Element(__kmSelectAll(this._root, css)[0] || null); }
  getElementById(id) {
    return new Element(__kmDescendants(this._root, (e) => __kmAttr(e, "id") === id)[0] || null);
  }
  getElementsByTagName(name) { return this.documentElement.getElementsByTagName(name); }
  getElementsByClassName(name) {
    return __kmWrapAll(__kmDescendants(this._root, (e) => __kmHasClass(e, name)));
  }
  attr(name) { return this.documentElement.attr(name); }
  hasAttr(name) { return this.documentElement.hasAttr(name); }
  xpath() { return __kmXpath(); }
  xpathFirst() { return __kmXpath(); }
}
''';
