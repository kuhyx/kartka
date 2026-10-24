/// JS part 5 of the Mangayomi shim: the six Kartka plugin functions
/// (contracts §6) implemented on a Mangayomi `MProvider`.
///
/// Mapping:
/// * `popular` / `latest` / `search` → `getPopular` / `getLatestUpdates` /
///   `search(query, page, getFilterList())`; `{list, hasNextPage}` →
///   `{items, hasNext}`. A source whose `supportsLatest` is false answers an
///   empty latest page. Chapter `dateUpload` (epoch ms string) becomes an
///   ISO-8601 `uploadedAt`; `number` is parsed from the chapter name.
/// * `details` and `chapters` both come from one memoised `getDetail(url)`.
///   A detail without `name` / `imageUrl` borrows the title / cover seen in
///   a listing (title falls back to the url).
/// * `pages` → `getPageList`; string entries or `{url, headers}`, with the
///   source's `getHeaders(url)` underneath per-page headers.
///
/// Expects `__kmExtClass` (the extension's `DefaultExtension`).
library;

/// JS source defining `popular`, `latest`, `search`, `details`, `chapters`
/// and `pages`.
const String kShimAdapterJs = r'''
const __kmStatus = ["ongoing", "completed", "onHiatus", "cancelled",
  "publishingFinished"];
const __kmSeen = new Map();
const __kmDetails = new Map();
let __kmInstance = null;

// Synchronous call with a fallback; a helper because js_interpreter does not
// catch a getter's throw in an inline try inside an async function.
function __kmTry(fn, fallback) {
  try { return fn(); } catch (_) { return fallback; }
}

async function __kmExt() {
  if (__kmInstance === null) __kmInstance = new __kmExtClass();
  await __kmLoadPrefs(__kmInstance);
  return __kmInstance;
}

function __kmStr(v) {
  return v === undefined || v === null || v === "" ? null : String(v);
}

function __kmPage(r) {
  const items = [];
  for (const m of (r && r.list) || []) {
    const url = __kmStr(m && m.link);
    if (url === null) continue;
    const title = __kmStr(m.name) || url;
    const coverUrl = __kmStr(m.imageUrl);
    if (__kmSeen.size > 2000) __kmSeen.clear();
    __kmSeen.set(url, { title: title, coverUrl: coverUrl });
    items.push({ url: url, title: title, coverUrl: coverUrl });
  }
  return { items: items, hasNext: !!(r && r.hasNextPage) };
}

async function popular(page) {
  const ext = await __kmExt();
  return __kmPage(await ext.getPopular(page));
}

async function latest(page) {
  const ext = await __kmExt();
  if (__kmTry(() => ext.supportsLatest, true) === false) {
    return { items: [], hasNext: false };
  }
  return __kmPage(await ext.getLatestUpdates(page));
}

async function search(query, page) {
  const ext = await __kmExt();
  let filters = [];
  try { filters = ext.getFilterList() || []; } catch (_) { filters = []; }
  return __kmPage(await ext.search(query, page, filters));
}

function __kmDetail(ext, url) {
  let p = __kmDetails.get(url);
  if (!p) {
    if (__kmDetails.size >= 8) __kmDetails.delete(__kmDetails.keys().next().value);
    p = Promise.resolve(ext.getDetail(url));
    p.catch(() => __kmDetails.delete(url));
    __kmDetails.set(url, p);
  }
  return p;
}

function __kmSplit(v) {
  if (Array.isArray(v)) return v.map((x) => String(x).trim()).filter((x) => x);
  const s = __kmStr(v);
  return s === null ? [] : s.split(/\s*,\s*/).filter((x) => x);
}

async function details(url) {
  const ext = await __kmExt();
  const m = (await __kmDetail(ext, url)) || {};
  const seen = __kmSeen.get(url) || {};
  const authors = __kmSplit(m.author);
  for (const a of __kmSplit(m.artist)) if (authors.indexOf(a) < 0) authors.push(a);
  return {
    url: url,
    title: __kmStr(m.name) || seen.title || url,
    coverUrl: __kmStr(m.imageUrl) || seen.coverUrl || null,
    authors: authors,
    description: __kmStr(m.description),
    genres: __kmSplit(m.genre),
    status: __kmStatus[m.status] || "unknown",
  };
}

// Best-effort chapter number: "Chapter 12.5", "Ch.3", "Episode 7", "#41";
// otherwise the first number that is not a volume number.
function __kmChapterNumber(name) {
  const s = String(name || "");
  const m = /\b(?:chapter|chap|ch|episode|ep)\.?\s*#?\s*(\d+(?:\.\d+)?)/i.exec(s) ||
    /#\s*(\d+(?:\.\d+)?)/.exec(s) ||
    /(\d+(?:\.\d+)?)/.exec(s.replace(/(?:volume|vol)\.?\s*\d+/ig, ""));
  return m ? parseFloat(m[1]) : null;
}

function __kmDate(v) {
  if (v === undefined || v === null || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? new Date(n).toISOString() : null;
}

async function chapters(url) {
  const ext = await __kmExt();
  const m = (await __kmDetail(ext, url)) || {};
  const out = [];
  for (const c of m.chapters || m.episodes || []) {
    const curl = __kmStr(c && c.url);
    if (curl === null) continue;
    const name = __kmStr(c.name) || curl;
    out.push({
      url: curl,
      name: name,
      number: __kmChapterNumber(name),
      uploadedAt: __kmDate(c.dateUpload),
      scanlator: __kmStr(c.scanlator),
    });
  }
  return out;
}

function __kmHeaders(ext, url) {
  try {
    const h = ext.getHeaders(url);
    return h && typeof h === "object" ? h : {};
  } catch (_) {
    return {};
  }
}

async function pages(url) {
  const ext = await __kmExt();
  const base = __kmHeaders(ext, url);
  const out = [];
  const seen = new Set();
  for (const p of (await ext.getPageList(url)) || []) {
    if (p === null || p === undefined) continue;
    const imageUrl = typeof p === "string" ? p.trim() : __kmStr(p.url);
    if (!imageUrl || seen.has(imageUrl)) continue;
    seen.add(imageUrl);
    const headers = {};
    const own = typeof p === "string" ? {} : p.headers || {};
    for (const k of Object.keys(base)) headers[k] = String(base[k]);
    for (const k of Object.keys(own)) headers[k] = String(own[k]);
    out.push({ imageUrl: imageUrl, headers: headers });
  }
  return out;
}
''';
