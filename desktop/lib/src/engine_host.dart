import 'dart:convert';
import 'dart:io';

/// A refusal the engine routes turn into [status] + `{"error": code}`.
class EngineError implements Exception {
  /// Creates the error.
  const new(this.status, this.code);

  /// HTTP status for the app.
  final int status;

  /// Short machine-readable reason.
  final String code;

  @override
  String toString() => 'EngineError($status, $code)';
}

/// What the `/engine/*` routes drive (docs/DOCS-contracts-webview.md §6).
abstract interface class EngineHost {
  /// Opens a blank page; returns its id.
  Future<String> createPage();

  /// Navigates page [id] to [url] with extra [headers].
  Future<void> navigate(String id, Uri url, Map<String, String> headers);

  /// Evaluates [expression] in page [id]; returns the JSON value.
  Future<Object?> evaluate(String id, String expression);

  /// Closes page [id] (unknown ids are ignored).
  Future<void> closePage(String id);

  /// Opens the visible interactive window on [url].
  Future<void> open(Uri url);

  /// Closes the window and registers [url]'s host for cookies.
  Future<void> finish(Uri url);

  /// The cookie header for [url] when its host is registered, else null.
  Future<String?> cookieHeader(Uri url);

  /// Stops every browser process.
  Future<void> stop();
}

/// Hosts with WebView cookies, persisted as a JSON list (0600).
class EngineHosts {
  /// Persists to [path].
  new(this.path);

  /// The JSON file.
  final String path;

  late final Set<String> _hosts = _read();

  Set<String> _read() {
    try {
      final raw = jsonDecode(File(path).readAsStringSync());
      return {if (raw is List) ...raw.whereType<String>()};
    } on Object {
      return {};
    }
  }

  /// Registers [host].
  void add(String host) {
    if (!_hosts.add(host.toLowerCase())) return;
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(_hosts.toList()));
    Process.runSync('chmod', ['600', path]);
  }

  /// Whether [url]'s host, or a parent domain, is registered.
  bool covers(Uri url) {
    final h = url.host.toLowerCase();
    return _hosts.any((r) => h == r || h.endsWith('.$r'));
  }
}
