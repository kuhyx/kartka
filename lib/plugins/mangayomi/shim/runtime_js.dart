/// JS part 4 of the Mangayomi shim: `MProvider`, `Client`,
/// `SharedPreferences`, `console` and the `String.prototype` helpers
/// Mangayomi exposes, built on `kartka.http` / `kartka.prefs` / `kartka.log`
/// (`atob`/`btoa` come from the runtime's polyfills).
/// Written for Kartka from Mangayomi's public extension API; no Mangayomi
/// code is used.
///
/// Expects `__kmSource` (the Mangayomi repo index entry) to be defined
/// before the extension runs.
library;

/// JS source defining the Mangayomi runtime globals.
const String kShimRuntimeJs = '''
// Extension logging always reaches the plugin log, whatever the engine has.
globalThis.console = {
  log: (...a) => kartka.log(...a),
  warn: (...a) => kartka.log(...a),
  error: (...a) => kartka.log(...a),
  info: (...a) => kartka.log(...a),
  debug: (...a) => kartka.log(...a),
};

function __kmFormEncode(map) {
  return Object.keys(map).map((k) => encodeURIComponent(k) + "=" +
    encodeURIComponent(map[k] == null ? "" : String(map[k]))).join("&");
}

// Mangayomi's Client never throws on HTTP errors: it answers
// {body, statusCode, headers}. Kartka only offers GET and POST.
async function __kmRequest(method, url, headers, body) {
  const h = {};
  if (headers && typeof headers === "object") {
    for (const k of Object.keys(headers)) h[k] = String(headers[k]);
  }
  let res;
  if (method === "GET") {
    res = await kartka.http.get(String(url), { headers: h });
  } else {
    let text = body;
    if (body != null && typeof body !== "string") {
      const type = Object.keys(h).find((k) => k.toLowerCase() === "content-type");
      const json = type && h[type].indexOf("application/json") >= 0;
      if (json || Array.isArray(body)) {
        text = JSON.stringify(body);
      } else {
        text = __kmFormEncode(body);
        if (!type) h["Content-Type"] = "application/x-www-form-urlencoded";
      }
    }
    res = await kartka.http.post(String(url), { headers: h, body: text == null ? "" : text });
  }
  return {
    body: res.body, statusCode: res.status, headers: res.headers || {},
    request: { url: String(url), method: method },
  };
}

class Client {
  constructor(options) { this.options = options; }
  get(url, headers) { return __kmRequest("GET", url, headers); }
  post(url, headers, body) { return __kmRequest("POST", url, headers, body); }
  head(url, headers) { return __kmRequest("GET", url, headers); }
  put() { throw new Error("Mangayomi shim: Client.put is not supported"); }
  patch() { throw new Error("Mangayomi shim: Client.patch is not supported"); }
  delete() { throw new Error("Mangayomi shim: Client.delete is not supported"); }
}

// Preference values live in `kartka.prefs` as JSON strings under "pref:<key>".
// They are loaded into this cache before every entry call, because
// Mangayomi's SharedPreferences is synchronous and kartka.prefs is not.
const __kmPrefCache = {};
let __kmPrefDefaults = null;

function __kmDefaultOf(pref) {
  const p = pref.listPreference;
  if (p) return (p.entryValues || [])[p.valueIndex || 0];
  const m = pref.multiSelectListPreference;
  if (m) return m.values || [];
  const s = pref.switchPreferenceCompat || pref.checkBoxPreference;
  if (s) return !!s.value;
  const e = pref.editTextPreference;
  if (e) return e.value == null ? "" : e.value;
  return undefined;
}

async function __kmLoadPrefs(ext) {
  if (__kmPrefDefaults === null) {
    __kmPrefDefaults = {};
    let list = [];
    try { list = ext.getSourcePreferences() || []; } catch (_) { list = []; }
    for (const pref of list) {
      if (pref && pref.key) __kmPrefDefaults[pref.key] = __kmDefaultOf(pref);
    }
  }
  for (const key of Object.keys(__kmPrefDefaults)) {
    const raw = await kartka.prefs.get("pref:" + key);
    if (raw == null) { delete __kmPrefCache[key]; continue; }
    try { __kmPrefCache[key] = JSON.parse(raw); } catch (_) { __kmPrefCache[key] = raw; }
  }
}

class SharedPreferences {
  get(key, fallback) {
    if (Object.prototype.hasOwnProperty.call(__kmPrefCache, key)) return __kmPrefCache[key];
    const d = __kmPrefDefaults ? __kmPrefDefaults[key] : undefined;
    return d === undefined ? (fallback === undefined ? null : fallback) : d;
  }
  getString(key, fallback) {
    const v = this.get(key, fallback);
    return v == null ? fallback : String(v);
  }
  setString(key, value) {
    __kmPrefCache[key] = value;
    kartka.prefs.set("pref:" + key, JSON.stringify(value));
  }
}

// Mangayomi adds Kotlin-style helpers to String.prototype; a missing
// delimiter returns the whole string.
function __kmStrHelper(name, fn) {
  if (!String.prototype[name]) {
    Object.defineProperty(String.prototype, name, { value: fn, writable: true, configurable: true });
  }
}
__kmStrHelper("substringAfter", function (d) {
  const i = this.indexOf(d);
  return i < 0 ? String(this) : this.slice(i + d.length);
});
__kmStrHelper("substringAfterLast", function (d) {
  const i = this.lastIndexOf(d);
  return i < 0 ? String(this) : this.slice(i + d.length);
});
__kmStrHelper("substringBefore", function (d) {
  const i = this.indexOf(d);
  return i < 0 ? String(this) : this.slice(0, i);
});
__kmStrHelper("substringBeforeLast", function (d) {
  const i = this.lastIndexOf(d);
  return i < 0 ? String(this) : this.slice(0, i);
});
__kmStrHelper("substringBetween", function (a, b) {
  return this.substringAfter(a).substringBefore(b);
});

function __kmNotImplemented(name) {
  return new Error(name + " not implemented");
}

class MProvider {
  get source() { return __kmSource; }
  get supportsLatest() { return true; }
  getHeaders(url) { return {}; }
  async getPopular(page) { throw __kmNotImplemented("getPopular"); }
  async getLatestUpdates(page) { throw __kmNotImplemented("getLatestUpdates"); }
  async search(query, page, filters) { throw __kmNotImplemented("search"); }
  async getDetail(url) { throw __kmNotImplemented("getDetail"); }
  async getPageList(url) { throw __kmNotImplemented("getPageList"); }
  getFilterList() { return []; }
  getSourcePreferences() { return []; }
}
''';
