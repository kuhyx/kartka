import 'dart:async';
import 'dart:js_interop';

import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/worker_script.dart';
import 'package:web/web.dart' as web;

/// Web engine: the plugin runs in a dedicated Web Worker created from a Blob.
///
/// The worker has no network or storage (see `kWorkerBanned`), and
/// [dispose] terminates it, which stops even a synchronous infinite loop.
class WorkerEngine implements JsEngine {
  web.Worker? _worker;
  String? _url;

  @override
  Future<void> start(String pluginSource, EngineMessageSink onMessage) async {
    final blob = web.Blob(
      [buildWorkerScript(pluginSource).toJS].toJS,
      web.BlobPropertyBag(type: 'text/javascript'),
    );
    final url = _url = web.URL.createObjectURL(blob);
    final worker = _worker = web.Worker(url.toJS);
    final ready = Completer<void>();
    worker
      ..onerror = ((web.Event e) {
        if (!ready.isCompleted) ready.completeError('worker error');
      }).toJS
      ..onmessage = ((web.MessageEvent e) {
        final json = (e.data! as JSString).toDart;
        if (ready.isCompleted) return onMessage(json);
        if (json.contains('"ready"')) return ready.complete();
        ready.completeError(json);
      }).toJS;
    await ready.future.timeout(const Duration(seconds: 10));
  }

  @override
  void post(String json) => _worker!.postMessage(json.toJS);

  @override
  Future<void> dispose() async {
    _worker?.terminate();
    _worker = null;
    final url = _url;
    if (url != null) web.URL.revokeObjectURL(url);
    _url = null;
  }
}

/// Platform hook for `engine_default.dart`.
JsEngine createPlatformEngine() => WorkerEngine();
