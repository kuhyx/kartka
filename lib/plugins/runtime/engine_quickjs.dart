import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/prelude.dart';

/// QuickJS engine (`flutter_js`, FFI). The Android default.
///
/// Never uses `getJavascriptRuntime`, which would enable `fetch`/XHR. The
/// `sendMessage`, timers and `console` are removed or replaced so only the
/// `kartka` global is left.
///
/// Known limit: flutter_js's interrupt `timeout` did not stop a synchronous
/// `while (true) {}` when tested, so it is not used. Per-call timeouts cover
/// awaited work only; a plugin that spins synchronously blocks the isolate.
class QuickJsEngine implements JsEngine {
  /// Creates an engine with the given limits.
  QuickJsEngine({this.memoryLimit});

  /// Heap cap in bytes; null leaves it unset (the bundled Linux test library
  /// lacks `jsSetMemoryLimit`, so the default must not call it).
  final int? memoryLimit;

  QuickJsRuntime2? _rt;

  /// Captures `sendMessage` into a closure, then removes ambient globals.
  static const String _bridgeJs = r'''
(function (g) {
  var s = g.sendMessage;
  g.__kartka_send = function (j) { s('kartka', JSON.stringify(j)); };
  delete g.sendMessage;
  g.setTimeout = undefined;
  g.console = {
    log: function () { g.kartka.log.apply(null, arguments); },
    warn: function () { g.kartka.log.apply(null, arguments); },
    error: function () { g.kartka.log.apply(null, arguments); }
  };
})(globalThis);
''';

  void _run(String code, String what) {
    final r = _rt!.evaluate(code);
    if (r.isError) throw StateError('$what: ${r.stringResult}');
  }

  @override
  Future<void> start(String pluginSource, EngineMessageSink onMessage) async {
    final rt = QuickJsRuntime2(memoryLimit: memoryLimit);
    _rt = rt;
    rt.onMessage('kartka', (dynamic a) => onMessage(a as String));
    _run(_bridgeJs, 'bridge');
    _run(kPreludeJs, 'prelude');
    _run(pluginSource, 'plugin');
    rt.executePendingJob();
  }

  @override
  void post(String json) {
    _run('__kartka_in(${jsonEncode(json)})', 'call');
    _rt!.executePendingJob();
  }

  @override
  Future<void> dispose() async {
    _rt?.dispose();
    _rt = null;
  }
}
