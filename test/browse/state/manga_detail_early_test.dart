import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSource src;
  late MangaDetailController c;

  setUp(() {
    src = FakeSource('mangadex');
    final sources = SourceRegistry([
      StaticSourceProvider([src]),
    ]);
    c = MangaDetailController(
      BrowseDeps(
        sources: sources,
        languages: BrowseLanguageStore(MemoryKeyValueStore()),
        chapters: ChapterStore(sources.byId, kv: MemoryKeyValueStore()),
        library: FakeLibrary(),
        progress: FakeProgress(),
        clock: () => DateTime.utc(2026, 11, 20),
      ),
      sourceId: 'mangadex',
      mangaUrl: '/m/1',
    );
  });

  test('details show while the slow chapter list is still loading '
      '(MangaFire: details 0.09 s, chapters 1-2.9 s; 9f7cad2f)', () async {
    src.chaptersGate = Completer<void>();
    final done = c.load();
    await _settle();
    expect(c.details?.title, 'Detail title');
    expect(c.chapters, isEmpty);
    expect(c.loading, isTrue);
    expect(c.listPending, isTrue);
    src.chaptersGate!.complete();
    await done;
    expect(c.chapters.map((ch) => ch.url), ['/c/1', '/c/2', '/c/3']);
    expect(c.listPending, isFalse);
    expect(c.error, isNull);
  });

  test('a failed chapter list takes the early details back, so the '
      'failure screen and Retry show as before', () async {
    src
      ..chaptersGate = Completer<void>()
      ..chaptersFail = Exception('list down');
    final done = c.load();
    await _settle();
    expect(c.details, isNotNull);
    src.chaptersGate!.complete();
    await done;
    expect(c.details, isNull);
    expect(c.error, isA<Exception>());
    expect(c.listPending, isFalse);
  });
}
