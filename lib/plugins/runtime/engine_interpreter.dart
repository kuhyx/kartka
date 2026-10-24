import 'dart:convert';

import 'package:js_interpreter/js_interpreter.dart';
import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/prelude.dart';

/// Pure-Dart engine (`js_interpreter`). Runs on every platform including the
/// Dart VM, so it backs `flutter test` end-to-end tests and works as a
/// fallback where QuickJS or a worker is unavailable. Slower than QuickJS and
/// cannot interrupt a synchronous infinite loop.
class InterpreterEngine implements JsEngine {
  JSInterpreter? _js;

  @override
  Future<void> start(String pluginSource, EngineMessageSink onMessage) async {
    final js = JSInterpreter();
    _js = js;
    js
      ..setGlobal('__kartka_send', (dynamic json) {
        onMessage('$json');
        return null;
      })
      ..eval(kPreludeJs)
      ..eval(pluginSource);
  }

  @override
  void post(String json) {
    _js!
      ..eval('__kartka_in(${jsonEncode(json)})')
      ..runPendingAsyncTasks();
  }

  @override
  Future<void> dispose() async => _js = null;
}
