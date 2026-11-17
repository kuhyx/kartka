import 'dart:convert';
import 'dart:io';

/// What `/proxy` answers instead of forwarding: a wrapper error ([error],
/// sent as a 502 with `x-kartka-proxy-error`), or a canned [status] and
/// [body].
class ProxyFault {
  /// A failure to reach the upstream at all.
  const new error(String this.error) : status = 502, body = null;

  /// A canned upstream answer.
  const new answer(int this.status, [this.body]) : error = null;

  /// The wrapper's error text, or null for a canned answer.
  final String? error;

  /// The status sent.
  final int? status;

  /// The body sent (JSON), if any.
  final String? body;
}

/// Agent-only fault injection for `/proxy` (`tools/agent` `fault` verb):
/// [file] maps a host (or `*`) to a mode, re-read on every request so a
/// flow can switch faults while the app runs. kuhy's real wrapper never
/// gets `--fault-file`, so it has none.
///
/// Modes: `offline` (a failed host lookup), `abort-once` (one dropped
/// connection per write of the file), `page-500` (Suwayomi page images
/// answer 500), `webview` / `upstream-dns` (the page list / details call
/// answers Suwayomi's GraphQL error for an upstream WebView timeout / DNS
/// failure), `gone` (the server no longer has the manga: its id lookup and
/// the title search come back empty).
class ProxyFaults {
  /// Faults read from [file].
  new(this.file);

  /// The JSON rules file; missing or broken means no faults.
  final File file;

  String? _rules;
  final _fired = <String>{};

  /// The fault for a request to [target] carrying [body], or null.
  ProxyFault? match(Uri target, List<int> body) {
    final mode = _modeFor(target.host);
    final host = target.host;
    return switch (mode) {
      'offline' => ProxyFault.error(
        "SocketException: Failed host lookup: '$host' "
        '(OS Error: No address associated with hostname, errno = 7)',
      ),
      'abort-once' when _fired.add(host) => const ProxyFault.error(
        'SocketException: Software caused connection abort',
      ),
      'page-500' when target.path.contains('/page/') => const ProxyFault.answer(
        500,
      ),
      'webview' when _operation(body) == 'KartkaPages' => _graphqlError(
        'Exception while fetching data (/fetchChapterPages) : '
        'Timed out waiting for WebView after 20s',
      ),
      'upstream-dns'
          when const {
            'KartkaDetails',
            'KartkaChapters',
          }.contains(_operation(body)) =>
        _graphqlError('www.upstream.invalid: Name or service not known'),
      'gone' when _operation(body) == 'KartkaMangaId' => _graphqlData({
        'mangas': {'nodes': <Object>[]},
      }),
      'gone' when _operation(body) == 'KartkaSourceManga' => _graphqlData({
        'fetchSourceManga': {'hasNextPage': false, 'mangas': <Object>[]},
      }),
      _ => null,
    };
  }

  String? _modeFor(String host) {
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
    if (text != _rules) {
      _rules = text;
      _fired.clear();
    }
    try {
      final rules = jsonDecode(text);
      if (rules is! Map<String, Object?>) return null;
      final mode = rules[host] ?? rules['*'];
      return mode is String ? mode : null;
    } on FormatException {
      return null;
    }
  }

  static String? _operation(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      return json is Map<String, Object?> && json['operationName'] is String
          ? json['operationName']! as String
          : null;
    } on FormatException {
      return null;
    }
  }

  static ProxyFault _graphqlData(Map<String, Object?> data) =>
      ProxyFault.answer(200, jsonEncode({'data': data}));

  static ProxyFault _graphqlError(String message) => ProxyFault.answer(
    200,
    jsonEncode({
      'errors': [
        {'message': message},
      ],
      'data': null,
    }),
  );
}
