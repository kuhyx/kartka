import 'dart:convert';
import 'dart:io';

/// `GET /sync-credentials`: a seeded Firebase session for the headless agent
/// instance (DOCS-contracts-runtime §17), served at most once per launch.
///
/// The file is `tool.seed_session --app kartka-agent`'s
/// `{id_token, refresh_token, expires_at}` (+ optional `email`), the shape
/// crdt_sync_flutter's `loadAccount(routes:)` adopts. Once a reply has
/// carried it, every later request gets 410: the app keeps the session in
/// its own store, so the credential is exposed for one boot, not for the
/// wrapper's lifetime. A refused, missing or malformed read consumes
/// nothing.
class SeedRoute {
  /// Serves the session in [path]; the log gets the path, never the content.
  new(this.path, this._log);

  /// The seeded session file.
  final String path;
  final void Function(String line) _log;
  bool _served = false;

  /// Answers GET only. Synchronous file reads, so two concurrent requests
  /// cannot both pass the [_served] check.
  void handle(HttpRequest request) {
    final response = request.response;
    // Every reply, not just the 200: Chromium keeps a 410 that carries no
    // explicit freshness fresh forever, so one cached "gone" in a persistent
    // profile hid every later launch's seed without asking the wrapper.
    response.headers.set('cache-control', 'no-store');
    if (request.method != 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    if (_served) {
      response.statusCode = HttpStatus.gone;
      return;
    }
    final body = _read();
    if (body == null) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    _served = true;
    response.headers.contentType = ContentType.json;
    response.write(body);
  }

  String? _read() {
    final file = File(path);
    if (!file.existsSync()) {
      _log('kartka-desktop: no seeded session at $path');
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException {
      // Never log the exception: its message quotes the source text.
      return _reject('is not JSON');
    }
    if (json is! Map<String, Object?>) return _reject('is not an object');
    final map = json;
    const fields = ['id_token', 'refresh_token', 'expires_at'];
    if (fields.any((f) => map[f] is! String)) {
      return _reject('lacks id_token/refresh_token/expires_at');
    }
    final email = map['email'];
    return jsonEncode({
      for (final f in fields) f: map[f],
      if (email is String) 'email': email,
    });
  }

  String? _reject(String why) {
    _log('kartka-desktop: $path $why; not serving it');
    return null;
  }
}
