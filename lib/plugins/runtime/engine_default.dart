import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/engine_unsupported.dart'
    if (dart.library.js_interop) 'package:kartka/plugins/runtime/engine_worker.dart'
    if (dart.library.ffi) 'package:kartka/plugins/runtime/engine_quickjs.dart'
    as impl;

/// The platform engine: QuickJS on Android, a Web Worker on web.
JsEngine createDefaultEngine() => impl.createPlatformEngine();
