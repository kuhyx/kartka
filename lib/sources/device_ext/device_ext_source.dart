import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_gone_error.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/platform/extension_runtime.dart';
import 'package:kartka/sources/device_ext/device_ext_api.dart';
import 'package:kartka/sources/suwayomi/legacy_urls.dart';
import 'package:kartka/sources/suwayomi/suwayomi_mappers.dart';

/// One source of an extension loaded in-app (Android).
///
/// Shares the `suwayomi:<id>` source ids and the Tachiyomi URLs with the
/// Suwayomi part, so library entries, history and `.tachibk` imports move
/// between the server and the phone untouched. Covers and pages are
/// [kartkaExtScheme] URLs: the bytes come through the extension's own
/// client, headers and interceptors included.
class DeviceExtSource implements MangaSource {
  /// Creates the source.
  new({required this.info, required this.runtime});

  /// What the runtime listed.
  final DeviceSourceInfo info;

  /// The Kotlin host.
  final ExtensionRuntime runtime;

  late final LegacyUrls? _legacy = legacyUrlsFor(info.id);

  String _url(String url) => _legacy?.mangaUrl(url) ?? url;

  @override
  SourceRef get ref => SourceRef(
    id: kartkaSourceId(info.id),
    name: info.name,
    lang: info.lang,
    origin: SourceOrigin.suwayomi,
  );

  Map<String, Object?> _args([Map<String, Object?> more = const {}]) => {
    'id': info.id,
    ...more,
  };

  @override
  Future<SearchPage> popular(int page) =>
      _page('popular', _args({'page': page}));

  @override
  Future<SearchPage> latest(int page) async => info.supportsLatest
      ? await _page('latest', _args({'page': page}))
      : SearchPage.empty;

  @override
  Future<SearchPage> search(String query, int page) =>
      _page('search', _args({'page': page, 'query': query}));

  Future<SearchPage> _page(String method, Map<String, Object?> args) async {
    final m = (await runtime.invoke(method, args))! as Map<Object?, Object?>;
    return SearchPage(
      items: [
        for (final e in m['mangas']! as List<Object?>)
          _summary(e! as Map<Object?, Object?>),
      ],
      hasNext: m['hasNextPage']! as bool,
    );
  }

  MangaSummary _summary(Map<Object?, Object?> m) => MangaSummary(
    sourceId: ref.id,
    url: m['url']! as String,
    title: m['title']! as String,
    coverUrl: _cover(m),
  );

  String? _cover(Map<Object?, Object?> m) {
    final thumb = _text(m['thumbnailUrl']);
    return thumb == null
        ? null
        : extImageUrl(info.id, index: 0, imageUrl: thumb);
  }

  /// [method] on the manga at [mangaUrl]. A site that answers 404, 410 or
  /// 451 (taken down) no longer has it, a state the screens show
  /// (4c696ac8: Atsumaru's 451 filed a ticket on every update check).
  Future<Object?> _manga(String method, String mangaUrl) async {
    try {
      return await runtime.invoke(method, _args({'url': _url(mangaUrl)}));
    } on ExtensionRuntimeException catch (e) {
      if (_gone.hasMatch(e.message)) throw DeviceExtMangaGone(ref.id, e);
      rethrow;
    }
  }

  static final _gone = RegExp(r'^HTTP error (404|410|451)$');

  @override
  Future<MangaDetails> details(String mangaUrl) async {
    final m = (await _manga('details', mangaUrl))! as Map<Object?, Object?>;
    final status = m['status'] as int? ?? 0;
    return MangaDetails(
      sourceId: ref.id,
      url: mangaUrl,
      title: m['title']! as String,
      coverUrl: _cover(m),
      authors: _list('${m['author'] ?? ''},${m['artist'] ?? ''}'),
      description: _text(m['description']),
      genres: _list('${m['genre'] ?? ''}'),
      status: status >= 0 && status < MangaStatus.values.length
          ? MangaStatus.values[status]
          : MangaStatus.unknown,
    );
  }

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    final list = (await _manga('chapters', mangaUrl))! as List<Object?>;
    return [
      for (final e in list)
        if (e case final Map<Object?, Object?> c)
          ChapterInfo(
            url: c['url']! as String,
            name: c['name']! as String,
            number: switch (c['number']) {
              final num n when n >= 0 => n.toDouble(),
              _ => null,
            },
            uploadedAt: switch (c['dateUpload']) {
              final int ms when ms > 0 => DateTime.fromMillisecondsSinceEpoch(
                ms,
                isUtc: true,
              ),
              _ => null,
            },
            scanlator: _text(c['scanlator']),
          ),
    ];
  }

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    final list =
        (await runtime.invoke('pages', _args({'url': chapterUrl})))!
            as List<Object?>;
    return [
      for (final (i, e) in list.indexed)
        if (e case final Map<Object?, Object?> p)
          PageRef(
            index: i,
            imageUrl: extImageUrl(
              info.id,
              index: p['index']! as int,
              url: p['url'] as String? ?? '',
              imageUrl: _text(p['imageUrl']),
            ),
          ),
    ];
  }
}

String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

List<String> _list(String csv) => {
  for (final s in csv.split(','))
    if (s.trim().isNotEmpty) s.trim(),
}.toList();

/// The site no longer serves this manga (HTTP 404, 410 or 451). Names the
/// source and the status only: the text is logged verbatim.
class DeviceExtMangaGone implements MangaGoneError {
  /// Creates the error for [sourceId] from the runtime's [cause].
  const new(this.sourceId, this.cause);

  /// Kartka source id.
  final String sourceId;

  /// What the extension reported.
  final ExtensionRuntimeException cause;

  @override
  String toString() => '$cause: gone from $sourceId';
}
