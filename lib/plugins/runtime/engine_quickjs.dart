import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_js/flutter_js.dart';
import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/prelude.dart';

/// QuickJS engine (`flutter_js`, FFI) evaluating on the CALLING isolate.
/// Use [QuickJsEngine], which hosts this in a background isolate.
///
/// Never uses `getJavascriptRuntime`, which would enable `fetch`/XHR. The
/// `sendMessage`, timers and `console` are removed or replaced so only the
/// `kartka` global is left.
///
/// flutter_js's interrupt `timeout` did not stop a synchronous
/// `while (true) {}` when tested, so it is not used; [QuickJsEngine] keeps
/// such a plugin off the UI isolate instead.
class InlineQuickJsEngine implements JsEngine {
  /// Creates an engine with the given limits.
  new({this.memoryLimit});

  /// Heap cap in bytes; null leaves it unset (the bundled Linux test library
  /// lacks `jsSetMemoryLimit`, so the default must not call it).
  final int? memoryLimit;

  QuickJsRuntime2? _rt;

  /// Captures `sendMessage` into a closure, then removes ambient globals.
  static const String _bridgeJs = '''
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

/// QuickJS in a background isolate: the Android engine.
///
/// A plugin spinning in JS blocks only that isolate, so the UI, per-call
/// timeouts and cancellation keep working. [dispose] kills the isolate; a
/// native loop that never returns to Dart may keep its thread until it ends,
/// but nothing waits on it any more.
class QuickJsEngine implements JsEngine {
  Isolate? _isolate;
  SendPort? _tx;
  ReceivePort? _rx;
  ReceivePort? _errors;

  @override
  Future<void> start(String pluginSource, EngineMessageSink onMessage) async {
    final rx = _rx = ReceivePort();
    final errors = _errors = ReceivePort();
    final ready = Completer<void>();
    // The error may arrive while spawn is still awaited; the final `await`
    // below still rethrows it.
    ready.future.ignore();
    rx.listen((m) {
      if (m is SendPort) {
        _tx = m..send(['start', pluginSource]);
        return;
      }
      final msg = m! as List<Object?>;
      switch (msg[0]) {
        case 'ready':
          ready.complete();
        case 'fail':
          ready.completeError(StateError('${msg[1]}'));
        default:
          onMessage('${msg[1]}');
      }
    });
    // An isolate that dies (or throws out of band) fails the pending calls.
    errors.listen((e) {
      final text = jsonEncode({'t': 'engine_error', 'error': '$e'});
      if (ready.isCompleted) return onMessage(text);
      ready.completeError(StateError('$e'));
    });
    _isolate = await Isolate.spawn(
      _isolateMain,
      rx.sendPort,
      onError: errors.sendPort,
    );
    await ready.future;
  }

  @override
  void post(String json) => _tx!.send(['post', json]);

  /// Test hook: behaves as if the isolate reported an uncaught [error].
  @visibleForTesting
  void debugInjectError(Object error) => _errors!.sendPort.send(error);

  /// Test hook: whether the last [dispose] saw the isolate exit by itself
  /// (false: it had to be killed; null: it was never asked to exit).
  @visibleForTesting
  bool? debugExitedCleanly;

  /// Frees the runtime inside its own isolate and lets that isolate exit by
  /// itself. Killing an isolate that still owns a live native runtime left
  /// QuickJS state behind, and the test shell crashed intermittently. A
  /// plugin spinning in native code cannot answer, so after [_exitGrace]
  /// the isolate is killed as before.
  @override
  Future<void> dispose() async {
    final isolate = _isolate;
    final tx = _tx;
    _isolate = null;
    _tx = null;
    if (isolate != null) {
      final exited = ReceivePort();
      isolate.addOnExitListener(exited.sendPort, response: _exited);
      if (tx != null) {
        tx.send(['dispose']);
        // A spinning plugin never answers: the grace timer ends the wait.
        final guard = Timer(_exitGrace, () => exited.sendPort.send(_timedOut));
        debugExitedCleanly = await exited.first == _exited;
        guard.cancel();
      }
      exited.close();
      isolate.kill(priority: Isolate.immediate);
    }
    _rx?.close();
    _errors?.close();
  }
}

/// How long [QuickJsEngine.dispose] waits for the isolate to free its
/// runtime and exit before killing it.
const Duration _exitGrace = Duration(seconds: 1);

const String _exited = 'exited';
const String _timedOut = 'timed out';

void _isolateMain(SendPort out) {
  final commands = ReceivePort();
  out.send(commands.sendPort);
  final engine = InlineQuickJsEngine();
  commands.listen((m) async {
    final cmd = m! as List<Object?>;
    try {
      if (cmd[0] == 'dispose') {
        try {
          await engine.dispose();
        } finally {
          commands.close();
        }
      } else if (cmd[0] == 'start') {
        await engine.start(
          cmd[1]! as String,
          (json) => out.send(['msg', json]),
        );
        out.send(['ready']);
      } else {
        engine.post(cmd[1]! as String);
      }
    } on Object catch (e) {
      out.send(
        cmd[0] == 'start'
            ? ['fail', '$e']
            : [
                'msg',
                jsonEncode({'t': 'engine_error', 'error': '$e'}),
              ],
      );
    }
  });
}

/// Platform hook for `engine_default.dart`.
JsEngine createPlatformEngine() => QuickJsEngine();
