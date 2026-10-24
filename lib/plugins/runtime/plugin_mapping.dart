import 'package:kartka/core/models/models.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

/// Converts plugin JSON (contracts section 1 shapes) into core models.
///
/// Any malformed result becomes a [PluginException] naming the plugin.
class PluginMapper {
  /// Creates a mapper for plugin [pluginId].
  const new(this.pluginId);

  /// Plugin id used in errors and `sourceId`.
  final String pluginId;

  String get _sourceId => 'plugin:$pluginId';

  T _guard<T>(PluginMethod m, T Function() body) {
    try {
      return body();
    } on PluginException {
      rethrow;
    } on Object catch (e) {
      throw PluginException(pluginId, 'invalid result: $e', method: m);
    }
  }

  /// `popular` / `latest` / `search` result.
  SearchPage page(PluginMethod m, Object? raw) => _guard(m, () {
    final json = _map(raw);
    return SearchPage(
      items: [for (final i in _list(json['items'])) _summary(_map(i))],
      hasNext: json['hasNext'] == true,
    );
  });

  /// `details` result.
  MangaDetails details(Object? raw) => _guard(PluginMethod.details, () {
    final j = _map(raw);
    return MangaDetails(
      sourceId: _sourceId,
      url: _str(j, 'url'),
      title: _str(j, 'title'),
      coverUrl: j['coverUrl'] as String?,
      authors: [for (final a in _list(j['authors'])) '$a'],
      description: j['description'] as String?,
      genres: [for (final g in _list(j['genres'])) '$g'],
      status: _status(j['status']),
      trackerIds: {
        for (final e in _map(j['trackerIds'] ?? const {}).entries)
          e.key: '${e.value}',
      },
    );
  });

  /// `chapters` result.
  List<ChapterInfo> chapters(Object? raw) => _guard(
    PluginMethod.chapters,
    () => [
      for (final c in _list(raw))
        ChapterInfo(
          url: _str(_map(c), 'url'),
          name: _str(_map(c), 'name'),
          number: _double(_map(c)['number']),
          uploadedAt: _date(_map(c)['uploadedAt']),
          scanlator: _map(c)['scanlator'] as String?,
        ),
    ],
  );

  /// `pages` result; `index` is the array position.
  List<PageRef> pages(Object? raw) => _guard(PluginMethod.pages, () {
    final out = <PageRef>[];
    for (final (i, p) in _list(raw).indexed) {
      final j = _map(p);
      out.add(
        PageRef(
          index: i,
          imageUrl: _str(j, 'imageUrl'),
          headers: {
            for (final e in _map(j['headers'] ?? const {}).entries)
              e.key: '${e.value}',
          },
        ),
      );
    }
    return out;
  });

  MangaSummary _summary(Map<String, Object?> j) => MangaSummary(
    sourceId: _sourceId,
    url: _str(j, 'url'),
    title: _str(j, 'title'),
    coverUrl: j['coverUrl'] as String?,
  );

  static Map<String, Object?> _map(Object? v) {
    if (v is Map) return v.cast<String, Object?>();
    throw FormatException('expected an object, got ${v.runtimeType}');
  }

  static List<Object?> _list(Object? v) {
    if (v == null) return const [];
    if (v is List) return v.cast<Object?>();
    throw FormatException('expected a list, got ${v.runtimeType}');
  }

  static String _str(Map<String, Object?> j, String key) {
    final v = j[key];
    if (v is String && v.isNotEmpty) return v;
    throw FormatException('"$key" missing or not a string');
  }

  static double? _double(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  static DateTime? _date(Object? v) {
    if (v is num) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    }
    return v is String ? DateTime.tryParse(v) : null;
  }

  static MangaStatus _status(Object? v) {
    if (v is int && v >= 0 && v < MangaStatus.values.length) {
      return MangaStatus.values[v];
    }
    return MangaStatus.values.asNameMap()[v] ?? MangaStatus.unknown;
  }
}
