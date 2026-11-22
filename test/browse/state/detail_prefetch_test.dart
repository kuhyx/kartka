import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/detail_prefetch.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

const _tile = MangaSummary(
  sourceId: 'mangadex',
  url: '/m/1',
  title: 'Tile title',
  coverUrl: 'https://img.test/tile.jpg',
);

/// On the desktop, Suwayomi's MangaFire details took 0.1-1.4 s and the
/// list 0.2-1.4 s (2026-11-22 agent), so a tap showed a blank details.load
/// spinner for up to 2.2 s (9f7cad2f). The tile already has the title and
/// cover, and a hover or press starts the fetches before the route opens.
void main() {
  late FakeSource src;
  late BrowseDeps deps;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 11, 22, 10);
    src = FakeSource('mangadex');
    final sources = SourceRegistry([
      StaticSourceProvider([src]),
    ]);
    deps = BrowseDeps(
      sources: sources,
      languages: BrowseLanguageStore(MemoryKeyValueStore()),
      chapters: ChapterStore(sources.byId, kv: MemoryKeyValueStore()),
      library: FakeLibrary(),
      progress: FakeProgress(),
      prefetch: DetailPrefetch(clock: () => now),
      clock: () => now,
    );
  });

  MangaDetailController open() =>
      MangaDetailController(deps, sourceId: 'mangadex', mangaUrl: '/m/1');

  test('a warmed tile opens on its title and cover at once, and the '
      'screen reuses the fetches the hover started', () async {
    src.detailsGate = Completer<void>();
    deps.prefetch.warm(deps, _tile);
    deps.prefetch.warm(deps, _tile); // a second hover starts nothing
    await _settle();
    expect(src.calls, ['details:/m/1', 'chapters:/m/1']);

    final c = open();
    final done = c.load();
    await _settle();
    expect(c.details?.title, 'Tile title');
    expect(c.details?.coverUrl, 'https://img.test/tile.jpg');
    expect(c.listPending, isTrue);

    src.detailsGate!.complete();
    await done;
    expect(c.details?.title, 'Detail title');
    expect(c.details?.description, 'A long description.');
    expect(c.chapters.map((ch) => ch.url), ['/c/1', '/c/2', '/c/3']);
    expect(src.calls, ['details:/m/1', 'chapters:/m/1']);
  });

  test('fresh details replace the tile while the list still loads', () async {
    src.chaptersGate = Completer<void>();
    deps.prefetch.warm(deps, _tile);
    final c = open();
    final done = c.load();
    await _settle();
    expect(c.details?.title, 'Detail title');
    expect(c.listPending, isTrue);
    src.chaptersGate!.complete();
    await done;
    expect(c.listPending, isFalse);
  });

  test('a failed prefetch shows the failure screen, as an open would', () {
    src.failWith = StateError('down');
    deps.prefetch.warm(deps, _tile);
    final c = open();
    return c.load().then((_) {
      expect(c.details, isNull);
      expect(c.error, isA<StateError>());
    });
  });

  test('an entry is used once, and an old one not at all', () async {
    deps.prefetch.warm(deps, _tile);
    expect(deps.prefetch.take(_tile.key), isNotNull);
    expect(deps.prefetch.take(_tile.key), isNull);

    deps.prefetch.warm(deps, _tile);
    now = now.add(const Duration(minutes: 3));
    expect(deps.prefetch.take(_tile.key), isNull);
    await _settle();
  });

  test('keeps the newest few and skips a source not listed', () async {
    for (var i = 0; i < 10; i++) {
      deps.prefetch.warm(deps, manga('mangadex', i));
    }
    expect(deps.prefetch.take(manga('mangadex', 0).key), isNull);
    expect(deps.prefetch.take(manga('mangadex', 9).key), isNotNull);
    deps.prefetch.warm(deps, manga('gone', 1));
    expect(deps.prefetch.take(manga('gone', 1).key), isNull);
    await _settle();
  });
}
