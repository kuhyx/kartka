import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/engine_unsupported.dart'
    if (dart.library.js_interop) 'package:kartka/platform/web/plugin_worker_engine.dart'
    if (dart.library.ffi) 'package:kartka/plugins/runtime/engine_quickjs.dart'
    as impl;

/// The platform engine: QuickJS on Android, a Web Worker on web.
JsEngine createDefaultEngine() => impl.createPlatformEngine();
