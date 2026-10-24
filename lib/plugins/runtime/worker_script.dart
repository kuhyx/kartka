import 'dart:convert';

import 'package:kartka/plugins/runtime/prelude.dart';

/// Globals removed from the worker before plugin code runs: everything that
/// could reach the network, storage or other contexts. Best effort (a script
/// can still reach `Function`), but the plugin gets no ambient I/O at all.
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
/// Protocol on top of the prelude: the worker posts `{t:'ready'}` once the
/// plugin evaluated, or `{t:'fail', error}`; afterwards both directions carry
/// the prelude's JSON messages as plain strings.
String buildWorkerScript(String pluginSource) =>
    '''
(function () {
  var post = self.postMessage.bind(self);
  var run = self.eval;
  self.__kartka_send = function (j) { post(j); };
  $kPreludeJs
  ${jsonEncode(kWorkerBanned)}.forEach(function (k) {
    try { self[k] = undefined; } catch (e) {}
  });
  self.onmessage = function (e) { self.__kartka_in(e.data); };
  try {
    (0, run)(${jsonEncode(pluginSource)});
    post('{"t":"ready"}');
  } catch (e) {
    post(JSON.stringify({ t: 'fail', error: String((e && e.message) || e) }));
  }
})();
''';
