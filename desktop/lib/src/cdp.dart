import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A CDP command answered with an error.
class CdpException implements Exception {
  /// Creates the error for [method].
  const new(this.method, this.message);

  /// The command that failed.
  final String method;

  /// Chromium's error message.
  final String message;

  @override
  String toString() => 'CdpException($method: $message)';
}

/// Minimal Chrome DevTools Protocol client over the browser websocket
/// (flattened sessions: page commands carry a `sessionId`).
class CdpClient {
  new _(this._socket) {
    _socket.listen(
      _onMessage,
      onDone: _failAll,
      // Same path as onDone; a socket error cannot be staged in tests.
      onError: (Object _) => _failAll(), // coverage:ignore-line
      cancelOnError: true,
    );
  }

  /// Connects to [url] (`ws://127.0.0.1:<port>/devtools/browser/<id>`).
  /// dart:io sends no `Origin`, which chromium would otherwise refuse.
  static Future<CdpClient> connect(Uri url) async =>
      CdpClient._(await WebSocket.connect('$url'));

  final WebSocket _socket;
  final Map<int, (String, Completer<Map<String, Object?>>)> _pending = {};
  int _seq = 0;
  bool _closed = false;

  /// Receives every event: (method, params, sessionId).
  void Function(String method, Map<String, Object?> params, String? session)?
  onEvent;

  /// Whether the socket is gone.
  bool get isClosed => _closed;

  /// Sends [method]; completes with its `result`, or throws [CdpException].
  Future<Map<String, Object?>> call(
    String method, {
    Map<String, Object?> params = const {},
    String? sessionId,
    Duration timeout = const Duration(seconds: 20),
  }) {
    if (_closed) {
      return Future.error(CdpException(method, 'browser connection closed'));
    }
    final id = ++_seq;
    final done = Completer<Map<String, Object?>>();
    _pending[id] = (method, done);
    _socket.add(
      jsonEncode({
        'id': id,
        'method': method,
        'params': params,
        'sessionId': ?sessionId,
      }),
    );
    return done.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw CdpException(method, 'timed out');
      },
    );
  }

  void _onMessage(Object? data) {
    final Object? msg;
    try {
      msg = jsonDecode('$data');
    } on FormatException {
      return;
    }
    if (msg is! Map) return;
    final waiting = _pending.remove(msg['id']);
    if (waiting == null) {
      final method = msg['method'];
      final params = msg['params'];
      final session = msg['sessionId'];
      if (method is String) {
        onEvent?.call(
          method,
          params is Map ? params.cast<String, Object?>() : const {},
          session is String ? session : null,
        );
      }
      return;
    }
    final (method, done) = waiting;
    final error = msg['error'];
    if (error is Map) {
      done.completeError(CdpException(method, '${error['message']}'));
    } else {
      final result = msg['result'];
      done.complete(result is Map ? result.cast<String, Object?>() : {});
    }
  }

  void _failAll() {
    _closed = true;
    for (final (method, done) in _pending.values) {
      done.completeError(CdpException(method, 'browser connection closed'));
    }
    _pending.clear();
  }

  /// Closes the socket.
  Future<void> close() async {
    _closed = true;
    await _socket.close();
  }
}
