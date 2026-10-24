/// Standard globals QuickJS and the interpreter lack, written fresh.
///
/// `atob`/`btoa` are needed by the bundled HTML parser (entity tables) and by
/// real-world plugins. Evaluated before the HTML parser bundle.
library;

/// The polyfill source (defines `atob` and `btoa` when missing).
const String kPolyfillsJs = r'''
(function (g) {
  var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  if (typeof g.btoa !== 'function') {
    g.btoa = function (input) {
      var s = String(input), out = '';
      for (var i = 0; i < s.length; i += 3) {
        var a = s.charCodeAt(i), b = s.charCodeAt(i + 1), c = s.charCodeAt(i + 2);
        if (a > 255 || b > 255 || c > 255) { throw new Error('btoa: invalid character'); }
        var n = (a << 16) | ((b || 0) << 8) | (c || 0);
        out += chars[(n >> 18) & 63] + chars[(n >> 12) & 63] +
          (i + 1 < s.length ? chars[(n >> 6) & 63] : '=') +
          (i + 2 < s.length ? chars[n & 63] : '=');
      }
      return out;
    };
  }
  if (typeof g.atob !== 'function') {
    g.atob = function (input) {
      var s = String(input).replace(/[\t\n\f\r =]/g, ''), out = '', bits = 0, acc = 0;
      for (var i = 0; i < s.length; i++) {
        var v = chars.indexOf(s[i]);
        if (v < 0) { throw new Error('atob: invalid character'); }
        acc = (acc << 6) | v;
        bits += 6;
        if (bits >= 8) { bits -= 8; out += String.fromCharCode((acc >> bits) & 255); }
      }
      return out;
    };
  }
})(globalThis);
''';
