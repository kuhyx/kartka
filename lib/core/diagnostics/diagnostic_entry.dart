import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/redact.dart';

/// One structured record in the diagnostics log (a failure, later perf).
///
/// Every string is passed through [redactUrlQueries] when serialised, so a
/// token or API key in a URL query never reaches the file a PC pulls.
class DiagnosticEntry {
  /// An entry of [kind] (dotted, e.g. `reader.advance`) at [at].
  const new({
    required this.at,
    required this.kind,
    required this.error,
    this.sourceId,
    this.mangaUrl,
    this.chapterUrl,
    this.stack = const [],
    this.route,
  });

  /// An entry for a caught [error], keeping the top [maxFrames] of [stack]
  /// and at most [maxErrorLength] characters of the message.
  factory failure({
    required DateTime at,
    required String kind,
    Object? error,
    StackTrace? stack,
    String? sourceId,
    String? mangaUrl,
    String? chapterUrl,
  }) {
    final message = '${error ?? 'unknown error'}';
    return DiagnosticEntry(
      at: at,
      kind: kind,
      error: message.length > maxErrorLength
          ? message.substring(0, maxErrorLength)
          : message,
      sourceId: sourceId,
      mangaUrl: mangaUrl,
      chapterUrl: chapterUrl,
      stack: _frames(stack),
    );
  }

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => DiagnosticEntry(
    at: readDate(json, 'at'),
    kind: readString(json, 'kind'),
    error: readString(json, 'error'),
    sourceId: readOptString(json, 'sourceId'),
    mangaUrl: readOptString(json, 'mangaUrl'),
    chapterUrl: readOptString(json, 'chapterUrl'),
    stack: [...?(json['stack'] as List<Object?>?)?.cast<String>()],
    route: readOptString(json, 'route'),
  );

  /// Stack frames kept by [DiagnosticEntry.failure].
  static const maxFrames = 5;

  /// Longest error message kept by [DiagnosticEntry.failure].
  static const maxErrorLength = 2000;

  /// When it happened.
  final DateTime at;

  /// What happened, dotted by area (`reader.advance`).
  final String kind;

  /// The error message.
  final String error;

  /// Source involved, if any.
  final String? sourceId;

  /// Manga involved, if any.
  final String? mangaUrl;

  /// Chapter involved, if any.
  final String? chapterUrl;

  /// The top stack frames, innermost first.
  final List<String> stack;

  /// The go_router pattern on top when it happened (never a location).
  final String? route;

  /// This entry with [route] set.
  DiagnosticEntry withRoute(String route) => DiagnosticEntry(
    at: at,
    kind: kind,
    error: error,
    sourceId: sourceId,
    mangaUrl: mangaUrl,
    chapterUrl: chapterUrl,
    stack: stack,
    route: route,
  );

  static List<String> _frames(StackTrace? stack) => [
    for (final line in '${stack ?? ''}'.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ].take(maxFrames).toList();

  /// JSON shape: UTC ISO-8601 [at], absent fields omitted, all redacted.
  Map<String, Object?> toJson() => {
    'at': writeDate(at),
    'kind': redactUrlQueries(kind),
    'error': redactUrlQueries(error),
    if (sourceId case final s?) 'sourceId': redactUrlQueries(s),
    if (mangaUrl case final m?) 'mangaUrl': redactUrlQueries(m),
    if (chapterUrl case final c?) 'chapterUrl': redactUrlQueries(c),
    if (stack.isNotEmpty) 'stack': [for (final f in stack) redactUrlQueries(f)],
    if (route case final r?) 'route': redactUrlQueries(r),
  };
}
