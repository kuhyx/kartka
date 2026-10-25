/// JS bootstrap shared by every engine (QuickJS and the web worker).
///
/// The engine supplies exactly one native function, `__kartka_send(json)`
/// (JS to Dart), and calls `__kartka_in(json)` for Dart to JS. Everything the
/// plugin can touch is built here, so all engines expose the same surface.
///
/// Wire format (JSON strings):
/// * JS to Dart `{t:'host', id?, op, args}`; `id` absent for fire-and-forget.
/// * JS to Dart `{t:'result', id, ok, value | error}` for a plugin call.
/// * Dart to JS `{t:'reply', id, ok, value | error}` answering a host call.
/// * Dart to JS `{t:'call', id, method, args}` invoking a plugin function.
library;

import 'package:kartka/plugins/runtime/html_parser_bundle.g.dart';
import 'package:kartka/plugins/runtime/polyfills.dart';

/// Everything evaluated before the plugin source: polyfills, the bundled HTML
/// parser, then the `kartka` object. `kartka.html` runs inside the sandbox
/// (synchronous, identical on Android and web); only http, prefs, log and
/// browser are host calls.
final String kPreludeJs = [
  kPolyfillsJs,
  kHtmlParserBundle,
  _kCoreJs,
].join('\n');

const String _kCoreJs = '''
(function (g) {
  var send = g.__kartka_send;
  var parseHtml = g.__kartka_html_parse;
  delete g.__kartka_html_parse;
  var pending = {};
  var seq = 0;
  function host(op, args) {
    return new Promise(function (resolve, reject) {
      var id = ++seq;
      pending[id] = { resolve: resolve, reject: reject };
      send(JSON.stringify({ t: 'host', id: id, op: op, args: args }));
    });
  }
  function opts(o) { return o === undefined || o === null ? {} : o; }
  var api = {
    http: {
      get: function (u, o) { return host('http.get', [String(u), opts(o)]); },
      post: function (u, o) { return host('http.post', [String(u), opts(o)]); }
    },
    html: {
      parse: function (h) { return parseHtml(String(h)); },
      select: function (h, c) {
        return parseHtml(String(h)).querySelectorAll(String(c)).map(function (e) {
          return { text: e.text.trim(), attrs: e.attributes, html: e.outerHTML };
        });
      }
    },
    log: function () {
      var parts = [];
      for (var i = 0; i < arguments.length; i++) { parts.push(String(arguments[i])); }
      send(JSON.stringify({ t: 'host', op: 'log', args: [parts.join(' ')] }));
    },
    prefs: {
      get: function (k) { return host('prefs.get', [String(k)]); },
      set: function (k, v) { return host('prefs.set', [String(k), String(v)]); }
    },
    browser: {
      load: function (u, o) { return host('browser.load', [String(u), opts(o)]); }
    }
  };
  Object.freeze(api.http); Object.freeze(api.html); Object.freeze(api.prefs);
  Object.freeze(api.browser);
  g.kartka = Object.freeze(api);
  function fail(id, e) {
    var msg = e && e.message ? e.message : String(e);
    send(JSON.stringify({ t: 'result', id: id, ok: false, error: msg }));
  }
  g.__kartka_in = function (json) {
    var m = JSON.parse(json);
    if (m.t === 'reply') {
      var p = pending[m.id];
      delete pending[m.id];
      if (!p) { return; }
      if (m.ok) { p.resolve(m.value); } else { p.reject(new Error(m.error)); }
    } else if (m.t === 'call') {
      var fn = g[m.method];
      if (typeof fn !== 'function') {
        fail(m.id, 'plugin does not define ' + m.method + '()');
        return;
      }
      try {
        Promise.resolve(fn.apply(null, m.args)).then(function (v) {
          var out = JSON.stringify(v === undefined ? null : v);
          send('{"t":"result","id":' + m.id + ',"ok":true,"value":' + out + '}');
        }, function (e) { fail(m.id, e); });
      } catch (e) { fail(m.id, e); }
    }
  };
  delete g.__kartka_send;
})(globalThis);
''';
