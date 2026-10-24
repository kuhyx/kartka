/// App route paths (DOCS-contracts §10).
///
/// Every dynamic segment is `Uri.encodeComponent`-encoded, so source URLs
/// containing `/`, `?` or `#` survive as one segment; the parsers decode.
library;

/// Path of the manga detail screen.
String mangaRoute(String sourceId, String mangaUrl) =>
    '/manga/${_e(sourceId)}/${_e(mangaUrl)}';

/// Path of the reader for one chapter.
String readRoute(String sourceId, String mangaUrl, String chapterUrl) =>
    '/read/${_e(sourceId)}/${_e(mangaUrl)}/${_e(chapterUrl)}';

/// go_router pattern matching [mangaRoute] paths.
const mangaRoutePattern = '/manga/:sourceId/:mangaUrl';

/// go_router pattern matching [readRoute] paths.
const readRoutePattern = '/read/:sourceId/:mangaUrl/:chapterUrl';

/// Decoded parts of a [mangaRoute] path, or `null` if [location] is not one.
({String sourceId, String mangaUrl})? parseMangaRoute(String location) {
  final s = _segments(location, 'manga', 2);
  return s == null ? null : (sourceId: s[0], mangaUrl: s[1]);
}

/// Decoded parts of a [readRoute] path, or `null` if [location] is not one.
({String sourceId, String mangaUrl, String chapterUrl})? parseReadRoute(
  String location,
) {
  final s = _segments(location, 'read', 3);
  return s == null ? null : (sourceId: s[0], mangaUrl: s[1], chapterUrl: s[2]);
}

String _e(String segment) => Uri.encodeComponent(segment);

/// Raw path segments after [head], decoded, if there are exactly [count].
List<String>? _segments(String location, String head, int count) {
  final Uri uri;
  try {
    uri = Uri.parse(location);
  } on FormatException {
    return null;
  }
  // Split the still-encoded path ourselves: Uri.pathSegments would decode
  // first, but an encoded segment may legitimately contain '/'.
  final raw = uri.path.split('/');
  if (raw.length != count + 2 || raw[0].isNotEmpty || raw[1] != head) {
    return null;
  }
  // Uri.parse already rejected malformed %-escapes, so decoding cannot fail.
  return [for (final s in raw.skip(2)) Uri.decodeComponent(s)];
}
