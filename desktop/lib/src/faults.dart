import 'dart:convert';
import 'dart:io';

/// What `/proxy` answers instead of forwarding: a wrapper error ([error],
/// sent as a 502 with `x-kartka-proxy-error`), a canned [status] and
/// [body], or the real answer after a [delay].
class ProxyFault {
  /// A failure to reach the upstream at all.
  const new error(String this.error)
    : status = 502,
      body = null,
      delay = null,
      rewrite = null;

  /// A canned upstream answer.
  const new answer(int this.status, [this.body])
    : error = null,
      delay = null,
      rewrite = null;

  /// The request is forwarded as usual, [delay] late.
  const new late(Duration this.delay)
    : error = null,
      status = null,
      body = null,
      rewrite = null;

  /// The request is forwarded at once and the answer's text goes through
  /// [rewrite] before the app sees it.
  const new rewritten(String Function(String) this.rewrite)
    : error = null,
      status = null,
      body = null,
      delay = null;

  /// Changes the upstream's answer text, or null to pass it through.
  final String Function(String)? rewrite;

  /// How long to hold the request before forwarding it, or null.
  final Duration? delay;

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
/// the title search come back empty), `slow-pages[:<ms>]` (the page list
/// call is forwarded [slowPages] or `<ms>` late: a slow `reader.open` for
/// `f4_reader_sweep.sh` to catch), `slow-details[:<ms>]` (the same for the
/// details and chapter-list calls: a slow upstream behind a detail open).
/// Both also hold MangaDex's matching REST calls (`f6_chapter_advance.sh`).
/// `slow-images[:<ms>]` holds page images the same way
/// (`f7_page_turns.sh`: a spinning page, `reader.page`). `hide-newest`
/// drops the newest chapter from MangaDex's chapter feed: browse a manga
/// with it on, clear it, and the reader meets a chapter released after
/// the stored list was saved.
class ProxyFaults {
  /// Faults read from [file].
  new(this.file);

  /// The default hold of `slow-pages` and `slow-details`.
  static const slowPages = Duration(seconds: 3);

  /// The GraphQL operations each `slow-*` mode holds back.
  static const _slowOperations = {
    'slow-pages': {'KartkaPages'},
    'slow-details': {'KartkaDetails', 'KartkaChapters'},
  };

  /// The JSON rules file; missing or broken means no faults.
  final File file;

  String? _rules;
  final _fired = <String>{};

  /// The fault for a request to [target] carrying [body], or null.
  ProxyFault? match(Uri target, List<int> body) {
    final mode = _modeFor(target.host);
    final host = target.host;
    final [slow, ...hold] = (mode ?? '').split(':');
    final ms = hold.isEmpty ? null : int.tryParse(hold.first);
    final late = ProxyFault.late(
      ms == null ? slowPages : Duration(milliseconds: ms),
    );
    if (slow == 'slow-images') return _isImage(target.path) ? late : null;
    if (_slowOperations[slow] case final operations?) {
      final op = _operation(body) ?? _restOperation(target.path);
      return operations.contains(op) ? late : null;
    }
    return switch (mode) {
      'hide-newest' when _isFirstFeedPage(target) => const ProxyFault.rewritten(
        _dropNewest,
      ),
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

  /// A page image: a file with an image extension (MangaDex's at-home
  /// `/data/...`, most CDNs) or a Suwayomi `/page/<n>` call.
  static bool _isImage(String path) =>
      RegExp(
        r'\.(png|jpe?g|webp|gif|avif)$',
        caseSensitive: false,
      ).hasMatch(path) ||
      RegExp(r'/page/\d+$').hasMatch(path);

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

  /// The GraphQL operation a MangaDex REST call stands for, so f6 can hold
  /// a built-in source's chapter list or page list too.
  static String? _restOperation(String path) => switch (path.split('/')) {
    ['', 'at-home', 'server', _] => 'KartkaPages',
    ['', 'manga', _, 'feed'] => 'KartkaChapters',
    ['', 'manga', _] => 'KartkaDetails',
    _ => null,
  };

  static bool _isFirstFeedPage(Uri target) =>
      _restOperation(target.path) == 'KartkaChapters' &&
      (target.queryParameters['offset'] ?? '0') == '0';

  /// MangaDex's feed newest first (volume, chapter desc) without its first
  /// chapter and that chapter's other uploads: as the list stood before
  /// the newest chapter came out. Text that is not a feed passes through.
  static String _dropNewest(String text) {
    try {
      final feed = jsonDecode(text);
      if (feed is! Map<String, Object?> || feed['data'] is! List) return text;
      final data = feed['data']! as List<Object?>;
      if (data.isEmpty) return text;
      String number(Object? c) {
        final a = c is Map ? c['attributes'] : null;
        return a is Map ? '${a['volume']}/${a['chapter']}' : '';
      }

      final newest = number(data.first);
      final kept = [
        for (final c in data)
          if (number(c) != newest) c,
      ];
      final total = feed['total'];
      return jsonEncode({
        ...feed,
        'data': kept,
        if (total is int) 'total': total - (data.length - kept.length),
      });
    } on FormatException {
      return text;
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
