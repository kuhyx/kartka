import 'dart:async';
import 'dart:convert';

import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/host_dispatch.dart';

/// Lets a caller abandon an in-flight plugin call.
class PluginCancelToken {
  final Completer<void> _c = Completer<void>();

  /// True once [cancel] ran.
  bool get isCancelled => _c.isCompleted;

  /// Completes when cancelled.
  Future<void> get whenCancelled => _c.future;

  /// Cancels every call using this token.
  void cancel() {
    if (!_c.isCompleted) _c.complete();
  }
}

/// One running plugin: owns the engine, the call protocol, timeouts and the
/// host dispatch. Every failure leaves as a [PluginException] naming the id.
class PluginSession {
  /// Creates a session; the engine boots lazily on the first [call].
  PluginSession({
    required this.manifest,
    required this.source,
    required this.services,
    required this.engineFactory,
    this.callTimeout = const Duration(seconds: 60),
    this.hostTimeout = const Duration(seconds: 30),
  }) : _host = HostDispatcher(services);

  /// Plugin identity (used in every error).
  final PluginManifest manifest;

  /// JS source of the plugin.
  final String source;

  /// Host API implementation.
  final PluginHostServices services;

  /// Builds the engine (again after a timeout kills it).
  final JsEngineFactory engineFactory;

  /// Max time for one plugin call.
  final Duration callTimeout;

  /// Max time for one host call (for example an HTTP request).
  final Duration hostTimeout;

  final HostDispatcher _host;
  final Map<int, Completer<Object?>> _calls = {};
  JsEngine? _engine;
  Future<void>? _starting;
  int _seq = 0;

  PluginException _err(String msg, [PluginMethod? m]) =>
      PluginException(manifest.id, msg, method: m);

  /// Calls plugin function [method] with JSON-able [args].
  Future<Object?> call(
    PluginMethod method,
    List<Object?> args, {
    PluginCancelToken? cancel,
    Duration? timeout,
  }) async {
    final m = method;
    try {
      await (_starting ??= _boot());
    } on PluginException {
      rethrow;
    } on Object catch (e) {
      _starting = null;
      throw _err('failed to load: $e', m);
    }
    final id = ++_seq;
    final done = Completer<Object?>();
    _calls[id] = done;
    final limit = timeout ?? callTimeout;
    final timer = Timer(limit, () {
      if (done.isCompleted) return;
      done.completeError(_err('timed out after ${limit.inSeconds}s', m));
      unawaited(_kill());
    });
    unawaited(
      cancel?.whenCancelled.then((_) {
        if (!done.isCompleted) done.completeError(_err('cancelled', m));
      }),
    );
    final msg = jsonEncode({'t': 'call', 'id': id, 'method': m.name, 'args': args});
    try {
      _engine!.post(msg);
      return await done.future;
    } on PluginException {
      rethrow;
    } on Object catch (e) {
      throw _err('$e', m);
    } finally {
      timer.cancel();
      _calls.remove(id);
    }
  }

  Future<void> _boot() async {
    final e = engineFactory();
    _engine = e;
    await e.start(source, (json) => _onMessage(e, json));
  }

  /// Stops the engine; pending calls fail. The next call reboots it.
  Future<void> _kill() async {
    final e = _engine;
    _engine = null;
    _starting = null;
    for (final c in _calls.values.toList()) {
      if (!c.isCompleted) c.completeError(_err('plugin restarted'));
    }
    await e?.dispose();
  }

  /// Releases the engine for good.
  Future<void> dispose() => _kill();

  void _onMessage(JsEngine from, String json) {
    final Map<String, Object?> m;
    try {
      m = jsonDecode(json) as Map<String, Object?>;
    } on Object {
      return; // Malformed message from the sandbox: ignore.
    }
    switch (m['t']) {
      case 'result':
        final c = _calls[m['id']];
        if (c == null || c.isCompleted) return;
        if (m['ok'] == true) {
          c.complete(m['value']);
        } else {
          c.completeError(_err('${m['error']}'));
        }
      case 'host':
        unawaited(_onHost(from, m));
    }
  }

  Future<void> _onHost(JsEngine from, Map<String, Object?> m) async {
    final id = m['id'];
    Map<String, Object?> reply;
    try {
      final args = (m['args'] as List?)?.cast<Object?>() ?? const [];
      final v = await _host.dispatch('${m['op']}', args).timeout(hostTimeout);
      reply = {'t': 'reply', 'id': id, 'ok': true, 'value': v};
    } on Object catch (e) {
      reply = {'t': 'reply', 'id': id, 'ok': false, 'error': '$e'};
    }
    // A reply for an engine that was killed meanwhile must not reach its
    // replacement (call ids restart there).
    if (id != null && identical(_engine, from)) from.post(jsonEncode(reply));
  }
}
