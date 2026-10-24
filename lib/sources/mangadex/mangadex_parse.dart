/// Pure readers over decoded MangaDex JSON (no I/O, no core models).
library;

/// A decoded JSON object.
typedef Json = Map<String, Object?>;

/// MangaDex `links` keys mapped to Kartka tracker ids.
const _trackerKeys = {'al': 'anilist', 'mal': 'mal', 'mu': 'mangaupdates'};

Json _obj(Object? raw) => raw is Map<String, Object?> ? raw : const {};

List<Json> _list(Object? raw) =>
    raw is List<Object?> ? [for (final e in raw) _obj(e)] : const [];

String? _text(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

String? _altIn(Json attrs, String lang) {
  for (final alt in _list(attrs['altTitles'])) {
    final t = _text(alt[lang]);
    if (t != null) return t;
  }
  return null;
}

/// Display title: the main or an alternative title in the first matching
/// language of [langs], then English, then whatever main title exists.
String pickTitle(Json attrs, List<String> langs) {
  final main = _obj(attrs['title']);
  for (final lang in [...langs, 'en']) {
    final t = _text(main[lang]) ?? _altIn(attrs, lang);
    if (t != null) return t;
  }
  return main.values.map(_text).nonNulls.firstOrNull ?? '';
}

/// Description in the first of [langs] that has one, then English.
String? pickDescription(Json attrs, List<String> langs) {
  final desc = _obj(attrs['description']);
  for (final lang in [...langs, 'en']) {
    final t = _text(desc[lang]);
    if (t != null) return t;
  }
  return null;
}

/// Tracker ids from `links` (`al`, `mal`, `mu`) for MangaDetails.trackerIds.
Map<String, String> trackerIds(Json attrs) {
  final links = _obj(attrs['links']);
  return {for (final e in _trackerKeys.entries) e.value: ?_text(links[e.key])};
}

/// Distinct `attributes.name` of relationships of [type], in order.
List<String> relNames(Json item, String type) => {
  for (final rel in _list(item['relationships']))
    if (rel['type'] == type) ?_text(_obj(rel['attributes'])['name']),
}.toList();

/// Cover file name from an expanded `cover_art` relationship.
String? coverFile(Json item) {
  for (final rel in _list(item['relationships'])) {
    if (rel['type'] != 'cover_art') continue;
    return _text(_obj(rel['attributes'])['fileName']);
  }
  return null;
}

/// English names of the manga's tags (genres, themes, formats).
List<String> tagNames(Json attrs) => [
  for (final tag in _list(attrs['tags']))
    ?_text(_obj(_obj(tag['attributes'])['name'])['en']),
];

/// "Vol. 2 Ch. 10.5 - Title", the bare title, or "Oneshot".
String chapterName(Json attrs) {
  final vol = _text(attrs['volume']);
  final ch = _text(attrs['chapter']);
  final title = _text(attrs['title']);
  final base = [
    if (vol != null) 'Vol. $vol',
    if (ch != null) 'Ch. $ch',
  ].join(' ');
  if (base.isEmpty) return title ?? 'Oneshot';
  return title == null ? base : '$base - $title';
}

/// Numeric chapter, or null when absent or not a number.
double? chapterNumber(Json attrs) {
  final ch = _text(attrs['chapter']);
  return ch == null ? null : double.tryParse(ch);
}

/// Publication instant of a chapter.
DateTime? publishedAt(Json attrs) {
  final raw = _text(attrs['publishAt']);
  return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
}

/// Scanlation groups joined with " & ", or null.
String? scanlator(Json chapter) {
  final names = relNames(chapter, 'scanlation_group');
  return names.isEmpty ? null : names.join(' & ');
}

/// Human-readable message of an API error body.
String apiError(Json body) {
  final first = _list(body['errors']).firstOrNull ?? const {};
  return _text(first['detail']) ?? _text(first['title']) ?? 'MangaDex error';
}
