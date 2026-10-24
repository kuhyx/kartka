import 'dart:async';
import 'dart:js_interop';

import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/worker_script.dart';
import 'package:web/web.dart' as web;

/// Web engine: the plugin runs in a blob Web Worker inside a hidden iframe
/// with `sandbox="allow-scripts"` (opaque origin) and a CSP of
/// `connect-src 'none'`. The only way out is a `MessageChannel` whose Dart end
/// carries the prelude protocol, so HTTP goes through `KartkaHttp` only.
///
/// [dispose] removes the iframe, which kills the worker even in a
/// synchronous infinite loop.
class WorkerEngine implements JsEngine {
  web.HTMLIFrameElement? _frame;
  web.MessagePort? _port;

  @override
  Future<void> start(String pluginSource, EngineMessageSink onMessage) async {
    final channel = web.MessageChannel();
    final port = _port = channel.port1;
    final ready = Completer<void>();
    port.onmessage = ((web.MessageEvent e) {
      final json = (e.data! as JSString).toDart;
      if (ready.isCompleted) return onMessage(json);
      if (json.contains('"ready"')) return ready.complete();
      ready.completeError(json);
    }).toJS;
    final frame = _frame =
        web.document.createElement('iframe') as web.HTMLIFrameElement
          ..setAttribute('sandbox', 'allow-scripts')
          ..style.display = 'none'
          ..srcdoc = buildHostPage(pluginSource).toJS;
    frame.onload = ((web.Event _) {
      frame.contentWindow!.postMessage(
        'kartka-init'.toJS,
        web.WindowPostMessageOptions(
          targetOrigin: '*',
          transfer: [channel.port2].toJS,
        ),
      );
    }).toJS;
    web.document.body!.append(frame);
    await ready.future.timeout(const Duration(seconds: 10));
  }

  @override
  void post(String json) => _port!.postMessage(json.toJS);

  @override
  Future<void> dispose() async {
    _port?.close();
    _port = null;
    _frame?.remove();
    _frame = null;
  }
}

/// Platform hook for `engine_default.dart`.
JsEngine createPlatformEngine() => WorkerEngine();
