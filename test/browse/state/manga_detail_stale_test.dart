import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

final _when = DateTime.utc(2026, 10, 29);

LibraryEntry _entry(String sourceId) => LibraryEntry(
  key: mangaKeyOf(sourceId, '/m/1'),
  sourceId: sourceId,
  mangaUrl: '/m/1',
  title: 'Stored title',
  coverUrl: 'https://img.test/stored.jpg',
  addedAt: _when,
  updatedAt: _when,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSource src;
  late FakeLibrary library;
  late FakeSourceProvider provider;
  late ChapterStore chapters;
  late BrowseDeps deps;

  setUp(() {
    src = FakeSource('mangadex');
    library = FakeLibrary();
    provider = FakeSourceProvider();
    final sources = SourceRegistry([
      StaticSourceProvider([src]),
      provider,
    ]);
    chapters = ChapterStore(sources.byId, kv: MemoryKeyValueStore());
    deps = BrowseDeps(
      sources: sources,
      languages: BrowseLanguageStore(MemoryKeyValueStore()),
      chapters: chapters,
      library: library,
      progress: FakeProgress(),
      clock: () => _when,
    );
  });

  test('renders the stored entry and chapters before the network', () async {
    await library.upsert(_entry('mangadex'));
    await chapters.load(mangaKeyOf('mangadex', '/m/1')); // a past visit
    src
      ..chapterList = const [ChapterInfo(url: '/c/9', name: 'Ch. 9')]
      ..detailsGate = Completer<void>();
    final c = MangaDetailController(
      deps,
      sourceId: 'mangadex',
      mangaUrl: '/m/1',
    );
    final done = c.load();
    await _settle();
    expect(c.details?.title, 'Stored title');
    expect(c.details?.coverUrl, 'https://img.test/stored.jpg');
    expect(c.chapters.map((ch) => ch.url), ['/c/1', '/c/2', '/c/3']);
    expect(c.loading, isTrue);
    src.detailsGate!.complete();
    await done;
    expect(c.details?.title, 'Detail title');
    expect(c.chapters.map((ch) => ch.url), ['/c/9']);
    expect(c.loading, isFalse);
  });

  test('a library entry without stored chapters still renders', () async {
    await library.upsert(_entry('mangadex'));
    src.detailsGate = Completer<void>();
    final c = MangaDetailController(
      deps,
      sourceId: 'mangadex',
      mangaUrl: '/m/1',
    );
    final done = c.load();
    await _settle();
    expect(c.details?.title, 'Stored title');
    expect(c.chapters, isEmpty);
    src.detailsGate!.complete();
    await done;
  });

  test('stored data shows while a runtime source is still missing', () async {
    await library.upsert(_entry('plugin:x'));
    final c = MangaDetailController(
      deps,
      sourceId: 'plugin:x',
      mangaUrl: '/m/1',
      sourceWait: const Duration(milliseconds: 50),
    );
    final done = c.load();
    await _settle();
    expect(c.details?.title, 'Stored title');
    await done;
    expect(c.error, isA<SourceUnavailable>());
    expect(c.details?.title, 'Stored title'); // kept, with the error
  });

  test('nothing stored: no details until the network answers', () async {
    src.detailsGate = Completer<void>();
    final c = MangaDetailController(
      deps,
      sourceId: 'mangadex',
      mangaUrl: '/m/1',
    );
    final done = c.load();
    await _settle();
    expect(c.details, isNull);
    src.detailsGate!.complete();
    await done;
    expect(c.details?.title, 'Detail title');
  });

  test('a failing library read only skips the stored view', () async {
    final c = MangaDetailController(
      BrowseDeps(
        sources: deps.sources,
        languages: deps.languages,
        chapters: chapters,
        library: _BrokenLibrary(),
        progress: FakeProgress(),
        clock: () => _when,
      ),
      sourceId: 'mangadex',
      mangaUrl: '/m/1',
    );
    await c.load();
    expect(c.details?.title, 'Detail title');
  });
}

class _BrokenLibrary extends FakeLibrary {
  @override
  Stream<List<LibraryEntry>> watch() => Stream.error(StateError('kv'));
}
