/// The JS every engine page runs (docs/DOCS-contracts-webview.md §2, §3).
///
/// One copy for both seams: Android evaluates these in the WebView, the
/// desktop wrapper evaluates them over CDP without knowing what they do.
library;

import 'dart:convert';

/// Every probe expression starts with this comment (lets fakes spot it).
const kEngineProbeMarker = '/*kartka-probe*/';

/// The probe: one JSON string `{ready, ran, matched, response, challenge,
/// href}` for the current document. Captcha / Turnstile widgets only count
/// on a near-empty page (a comment form's captcha is not a wall); the
/// Cloudflare and DDoS-Guard interstitial markers always count.
String engineProbeJs(String? waitFor) =>
    '$kEngineProbeMarker(function (sel) {\n'
    '$_probeBody'
    '})(${jsonEncode(waitFor)})';

const _probeBody = '''
  var d = document, w = window;
  function q(s) { try { return d.querySelector(s); } catch (e) { return null; } }
  var t = (d.title || '').toLowerCase();
  var text = d.body ? (d.body.innerText || '').length : 0;
  var sparse = text < 3000;
  var ch = null;
  if (t.indexOf('just a moment') >= 0 || t.indexOf('attention required') >= 0 ||
      q('#challenge-form') || q('#cf-challenge-running') ||
      q('iframe[src*="challenges.cloudflare.com"]') ||
      (sparse && q('.cf-turnstile'))) {
    ch = 'cloudflare';
  } else if (t.indexOf('ddos-guard') >= 0) {
    ch = 'ddos-guard';
  } else if (sparse && (q('.g-recaptcha') || q('.h-captcha') ||
      q('iframe[src*="recaptcha"]') || q('iframe[src*="hcaptcha.com"]'))) {
    ch = 'captcha';
  }
  return JSON.stringify({
    ready: d.readyState,
    ran: w.__kartkaRan === true,
    matched: sel === null || q(sel) !== null,
    response: typeof w.__kartkaResponse === 'string' ? w.__kartkaResponse : null,
    challenge: ch,
    href: String(location.href)
  });
''';

/// Installed once per document before the request's scripts: marks the
/// document as done and offers `kartka.respond(s)` plus Mangayomi's
/// `window.flutter_inappwebview.callHandler('setResponse', s)`. The first
/// response wins.
const kEngineHookJs = '''
(function (w) {
  w.__kartkaRan = true;
  try { performance.setResourceTimingBufferSize(10000); } catch (e) {}
  function set(v) {
    if (typeof w.__kartkaResponse !== 'string') { w.__kartkaResponse = String(v); }
  }
  w.kartka = w.kartka || {};
  w.kartka.respond = set;
  w.flutter_inappwebview = w.flutter_inappwebview || {};
  w.flutter_inappwebview.callHandler = function (name) {
    if (name === 'setResponse') { set(arguments[1]); }
    return Promise.resolve(null);
  };
})(window);
''';

/// The snapshot: one JSON string `{html, resources, status, href}`.
const kEngineSnapshotJs = '''
(function () {
  var seen = {}, out = [];
  function add(u) {
    if (u && !seen[u] && /^https?:/.test(u)) { seen[u] = 1; out.push(u); }
  }
  try {
    performance.getEntriesByType('resource').forEach(function (e) { add(e.name); });
  } catch (e) {}
  Array.prototype.forEach.call(document.images, function (i) {
    add(i.currentSrc || i.src);
  });
  var nav = null;
  try { nav = performance.getEntriesByType('navigation')[0]; } catch (e) {}
  return JSON.stringify({
    html: document.documentElement ? document.documentElement.outerHTML : '',
    resources: out,
    status: nav && nav.responseStatus ? nav.responseStatus : null,
    href: String(location.href)
  });
})()
''';

/// Decodes what an engine hands back for a JSON-string expression. CDP
/// returns the string itself; Android WebViews may return it JSON-quoted
/// once more. Non-JSON strings come back unchanged.
Object? decodeEngineValue(Object? raw) {
  if (raw is! String) return raw;
  Object? once;
  try {
    once = jsonDecode(raw);
  } on FormatException {
    return raw;
  }
  if (once is! String) return once;
  try {
    return jsonDecode(once);
  } on FormatException {
    return once;
  }
}
