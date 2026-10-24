/// JS bootstrap shared by every engine (QuickJS, interpreter, web worker).
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

/// The prelude source. Evaluated before the plugin source.
const String kPreludeJs = r'''
(function (g) {
  var send = g.__kartka_send;
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
      select: function (h, c) { return host('html.select', [String(h), String(c)]); }
    },
    log: function () {
      var parts = [];
      for (var i = 0; i < arguments.length; i++) { parts.push(String(arguments[i])); }
      send(JSON.stringify({ t: 'host', op: 'log', args: [parts.join(' ')] }));
    },
    prefs: {
      get: function (k) { return host('prefs.get', [String(k)]); },
      set: function (k, v) { return host('prefs.set', [String(k), String(v)]); }
    }
  };
  Object.freeze(api.http); Object.freeze(api.html); Object.freeze(api.prefs);
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
