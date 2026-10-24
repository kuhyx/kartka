import 'dart:convert';

import 'package:kartka/plugins/runtime/prelude.dart';

/// Globals removed from the worker before plugin code runs. Defence in depth:
/// the real boundary is the host page's CSP (`connect-src 'none'`) and its
/// opaque origin, see [buildHostPage].
const List<String> kWorkerBanned = [
  'fetch',
  'XMLHttpRequest',
  'WebSocket',
  'EventSource',
  'WebTransport',
  'importScripts',
  'indexedDB',
  'caches',
  'Worker',
  'SharedWorker',
  'BroadcastChannel',
  'postMessage',
  'eval',
];

/// Source of the Web Worker that hosts one plugin.
///
/// The worker waits for one message `{port}` (a `MessagePort` whose other end
/// is the Dart side), then runs the prelude and plugin. It posts
/// `{t:'ready'}` on that port once the plugin evaluated, or `{t:'fail',
/// error}`; afterwards both directions carry the prelude's JSON strings.
String buildWorkerScript(String pluginSource) =>
    '''
(function () {
  var run = self.eval;
  self.onmessage = function (first) {
    var port = first.data.port;
    self.onmessage = null;
    var send = function (j) { port.postMessage(j); };
    self.__kartka_send = send;
    $kPreludeJs
    ${jsonEncode(kWorkerBanned)}.forEach(function (k) {
      try { self[k] = undefined; } catch (e) {}
    });
    port.onmessage = function (e) { self.__kartka_in(e.data); };
    try {
      (0, run)(${jsonEncode(pluginSource)});
      send('{"t":"ready"}');
    } catch (e) {
      send(JSON.stringify({ t: 'fail', error: String((e && e.message) || e) }));
    }
  };
})();
''';

/// HTML of the hidden sandboxed iframe that spawns the worker.
///
/// Served as `srcdoc` into `<iframe sandbox="allow-scripts">` (no
/// `allow-same-origin`): the frame has an opaque origin, so it cannot read the
/// app's IndexedDB, cookies or localStorage. Its CSP allows no network at all,
/// and the blob worker it creates inherits that policy.
String buildHostPage(String pluginSource) {
  // `</` and `<!--` must not appear raw inside an inline script element.
  final script = jsonEncode(buildWorkerScript(pluginSource))
      .replaceAll('</', r'<\/')
      .replaceAll('<!--', r'<\!--');
  return '''
<!doctype html><html><head>
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob:; worker-src blob:; connect-src 'none'">
</head><body><script>
var WORKER_SRC = $script;
addEventListener('message', function (e) {
  if (!e.ports.length) { return; }
  var url = URL.createObjectURL(new Blob([WORKER_SRC], { type: 'text/javascript' }));
  var w = new Worker(url);
  w.postMessage({ port: e.ports[0] }, [e.ports[0]]);
});
</script></body></html>
''';
}
