import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/detail_store.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

final _when = DateTime.utc(2026, 10, 29);
final MangaKey _key = mangaKeyOf('mangadex', '/m/1');

final _entry = LibraryEntry(
  key: _key,
  sourceId: 'mangadex',
  mangaUrl: '/m/1',
  title: 'Stored title',
  coverUrl: 'https://img.test/thumb.jpg',
  addedAt: _when,
  updatedAt: _when,
);

void main() {
  late FakeSource src;
  late FakeLibrary library;
  late MemoryKeyValueStore kv;
  late BrowseDeps deps;

  setUp(() {
    src = FakeSource('mangadex');
    library = FakeLibrary();
    kv = MemoryKeyValueStore();
    final sources = SourceRegistry([
      StaticSourceProvider([src]),
    ]);
    deps = BrowseDeps(
      sources: sources,
      languages: BrowseLanguageStore(MemoryKeyValueStore()),
      chapters: ChapterStore(sources.byId, kv: kv),
      library: library,
      progress: FakeProgress(),
      details: DetailStore(kv),
      clock: () => _when,
    );
  });

  MangaDetailController open() =>
      MangaDetailController(deps, sourceId: 'mangadex', mangaUrl: '/m/1');

  test('a reopen shows the last fetched details before the network', () async {
    await library.upsert(_entry);
    await open().load(); // a past visit, network answered
    src.detailsGate = Completer<void>();
    final c = open();
    final done = c.load();
    await pumpEventQueue();
    expect(c.loading, isTrue, reason: 'the network is still out');
    expect(c.details?.authors, ['Author A']);
    expect(c.details?.status, MangaStatus.ongoing);
    expect(c.details?.description, 'A long description.');
    expect(
      c.details?.coverUrl,
      'https://img.test/thumb.jpg',
      reason: "the library grid's cover: a memory hit, drawn this frame",
    );
    src.detailsGate!.complete();
    await done;
    expect(c.details?.title, 'Detail title', reason: 'fresh details');
    expect(
      c.details?.coverUrl,
      'https://img.test/thumb.jpg',
      reason: 'the shown cover is never swapped for a cold url',
    );
    expect(
      (await DetailStore(kv).read(_key))?.coverUrl,
      'https://img.test/cover.jpg',
      reason: 'the store keeps what the source said',
    );
  });

  test('a manga outside the library stores no details', () async {
    await open().load();
    expect(await DetailStore(kv).read(_key), isNull);
    final c = open();
    await c.load();
    await c.setInLibrary(add: true);
    expect((await DetailStore(kv).read(_key))?.authors, ['Author A']);
    await c.setInLibrary(add: false);
    expect(await DetailStore(kv).read(_key), isNull);
  });

  test('a corrupt or absent store reads as nothing', () async {
    await kv.set('browse.details.${mangaKeyHash(_key)}', '{bad');
    expect(await DetailStore(kv).read(_key), isNull);
    const none = DetailStore(null);
    await none.write(_key, await src.details('/m/1'));
    expect(await none.read(_key), isNull);
    await none.remove(_key);
  });
}
