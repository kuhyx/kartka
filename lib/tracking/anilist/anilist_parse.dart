/// Maps AniList GraphQL response bodies onto the §9 tracker types.
library;

import 'package:kartka/tracking/common/tracker.dart';

/// An AniList GraphQL error, whatever HTTP status carried it.
class AniListException implements Exception {
  /// Creates an error with AniList's [message] and optional [status].
  const AniListException(this.message, {this.status});

  /// Error text from the `errors` array.
  final String message;

  /// Status from the error object (AniList mirrors the HTTP status there).
  final int? status;

  /// The stored token is unusable: AniList answers `Invalid token` with 400.
  bool get isAuthError =>
      status == 401 || message.toLowerCase().contains('invalid token');

  /// The request hit the rate limit.
  bool get isRateLimited => status == 429;

  @override
  String toString() => 'AniListException($status): $message';
}

/// Search hits from a `Page { media }` response.
List<TrackSearchResult> parseSearch(Map<String, Object?> body) {
  final page = _map(_data(body)['Page']);
  final media = page['media'];
  if (media is! List) return const [];
  return [
    for (final m in media.whereType<Map<String, Object?>>()) _searchHit(m),
  ];
}

/// The viewer's list entry from a `Media { mediaListEntry }` response.
TrackStatus? parseFetch(Map<String, Object?> body) {
  final media = _data(body)['Media'];
  if (media is! Map<String, Object?>) return null;
  final entry = media['mediaListEntry'];
  if (entry is! Map<String, Object?>) return null;
  final score = (entry['score'] as num?)?.toDouble();
  return TrackStatus(
    remoteId: '${media['id']}',
    chaptersRead: (entry['progress'] as num?)?.toInt() ?? 0,
    totalChapters: (media['chapters'] as num?)?.toInt(),
    status: entry['status'] as String? ?? 'CURRENT',
    score: score == null || score == 0 ? null : score,
  );
}

/// Stored progress from a `SaveMediaListEntry` response.
int parseSaved(Map<String, Object?> body) {
  final saved = _map(_data(body)['SaveMediaListEntry']);
  return (saved['progress'] as num?)?.toInt() ?? 0;
}

TrackSearchResult _searchHit(Map<String, Object?> m) {
  final title = m['title'] is Map<String, Object?>
      ? m['title']! as Map<String, Object?>
      : const <String, Object?>{};
  final cover = m['coverImage'] is Map<String, Object?>
      ? (m['coverImage']! as Map<String, Object?>)['large'] as String?
      : null;
  return TrackSearchResult(
    remoteId: '${m['id']}',
    title:
        (title['userPreferred'] ?? title['english'] ?? title['romaji'])
            as String? ??
        '${m['id']}',
    coverUrl: cover,
    chapters: (m['chapters'] as num?)?.toInt(),
  );
}

Map<String, Object?> _data(Map<String, Object?> body) {
  final errors = body['errors'];
  if (errors != null) {
    final first = errors is List && errors.isNotEmpty ? errors.first : null;
    final e = first is Map<String, Object?> ? first : const <String, Object?>{};
    throw AniListException(
      e['message'] as String? ?? 'unknown AniList error',
      status: (e['status'] as num?)?.toInt(),
    );
  }
  return _map(body['data']);
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  throw AniListException('malformed AniList response: $value');
}
