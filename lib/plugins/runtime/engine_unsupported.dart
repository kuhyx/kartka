import 'package:kartka/plugins/runtime/engine.dart';

/// Neither FFI nor a browser worker exists: plugins cannot run here.
JsEngine createPlatformEngine() =>
    throw UnsupportedError('no JavaScript engine on this platform');
