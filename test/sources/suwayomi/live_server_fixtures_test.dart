import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_mappers.dart';

/// Cross-checks the mappers against the deploy part's responses from the
/// real server (test/fixtures/suwayomi/*.json, recorded by agent/suwayomi),
/// not only against the client's own recordings in client/.
Map<String, Object?> _data(String name) {
  final raw = File('test/fixtures/suwayomi/$name.json').readAsStringSync();
  return (jsonDecode(raw) as Map<String, Object?>)['data']!
      as Map<String, Object?>;
}

List<Map<String, Object?>> _list(Object? v) => [
  for (final e in v! as List<Object?>) e! as Map<String, Object?>,
];

String _resolve(String p) => 'https://suwayomi.example$p';

void main() {
  test('sources', () {
    final nodes = _list((_data('sources')['sources']! as Map)['nodes']);
    final infos = nodes.map(SuwayomiSourceInfo.fromJson).toList();
    expect(infos.map((i) => i.ref.id), everyElement(startsWith('suwayomi:')));
    expect(infos.map((i) => i.serverId), contains('2499283573021220255'));
  });

  test('popular, latest and search pages', () {
    for (final kind in ['popular', 'latest', 'search']) {
      final payload =
          _data('fetch_source_manga_$kind')['fetchSourceManga']! as Map;
      final items = [
        for (final m in _list(payload['mangas']))
          mangaSummaryFrom(m, 'suwayomi:1', _resolve),
      ];
      expect(items, isNotEmpty, reason: kind);
      expect(items.first.coverUrl, startsWith('https://suwayomi.example/api'));
    }
  });

  test('details, chapters and pages', () {
    final manga =
        (_data('fetch_manga')['fetchMangaAndChapters']! as Map)['manga']!
            as Map<String, Object?>;
    final details = mangaDetailsFrom(manga, 'suwayomi:1', _resolve);
    expect(details.title, isNotEmpty);
    expect(details.status, isNot(MangaStatus.unknown));

    final chapters = _list(
      (_data('fetch_chapters')['fetchMangaAndChapters']! as Map)['chapters'],
    ).map(chapterFrom).toList();
    expect(chapters, isNotEmpty);
    expect(chapters.where((c) => c.uploadedAt != null), isNotEmpty);

    final pages =
        (_data('fetch_chapter_pages')['fetchChapterPages']! as Map)['pages']!
            as List<Object?>;
    final refs = pageRefsFrom(pages, _resolve, const {'Authorization': 'x'});
    expect(refs.first.imageUrl, startsWith('https://suwayomi.example/api/'));
  });

  test('extensions', () {
    final nodes = _list((_data('extensions')['extensions']! as Map)['nodes']);
    final parsed = sortExtensions([
      for (final n in nodes) SuwayomiExtension.fromJson(n, _resolve),
    ]);
    expect(parsed, isNotEmpty);
    expect(parsed.first.iconUrl, startsWith('https://suwayomi.example/'));
  });
}
