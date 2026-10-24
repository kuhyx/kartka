import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/engine_interpreter.dart';

/// Fallback when neither FFI nor a browser worker exists: pure Dart.
JsEngine createPlatformEngine() => InterpreterEngine();
