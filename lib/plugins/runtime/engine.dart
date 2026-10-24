/// Minimal engine seam: one sandboxed JS context per installed plugin.
///
/// Engines only move JSON strings; `PluginSession` owns protocol, timeouts and
/// host dispatch, so an engine is ~30 lines and trivially fakeable.
library;

/// Receives JS to Dart messages (JSON strings, see `prelude.dart`).
typedef EngineMessageSink = void Function(String json);

/// A sandboxed JavaScript context.
abstract interface class JsEngine {
  /// Boots the sandbox: defines `__kartka_send`, runs the prelude and then
  /// [pluginSource]. Throws if either fails to evaluate.
  Future<void> start(String pluginSource, EngineMessageSink onMessage);

  /// Delivers a Dart to JS message to `__kartka_in` and drains pending jobs.
  void post(String json);

  /// Tears the sandbox down; a runaway script must stop executing.
  Future<void> dispose();
}

/// Creates a fresh, unstarted engine.
typedef JsEngineFactory = JsEngine Function();
