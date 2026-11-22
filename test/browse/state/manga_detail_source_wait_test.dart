import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

Future<void> _tick() => Future<void>.delayed(Duration.zero);

/// A source absent once every provider has listed fails at once: a
/// library entry on a dead Suwayomi source timed its bar for the whole
/// 10 s source wait (`details.refresh` 9840 ms, 2d26b6d5).
void main() {
  BrowseDeps deps(SourceRegistry sources) => BrowseDeps(
    sources: sources,
    languages: BrowseLanguageStore(MemoryKeyValueStore()),
    chapters: ChapterStore(sources.byId),
    library: FakeLibrary(),
    progress: FakeProgress(),
    clock: () => DateTime.utc(2026, 11, 22),
  );

  MangaDetailController open(SourceRegistry sources, String id) =>
      MangaDetailController(deps(sources), sourceId: id, mangaUrl: '/m/1');

  test('a source absent from settled lists fails at once', () async {
    final live = FakeSourceProvider();
    final sources = SourceRegistry([
      StaticSourceProvider([FakeSource('mangadex')]),
      live,
    ]);
    live.controller.add([FakeSource('suwayomi:1')]);
    await _tick();
    final watch = Stopwatch()..start();
    final c = open(sources, 'suwayomi:dead');
    await c.load();
    expect(c.error, isA<SourceUnavailable>());
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });

  test('a provider that has not listed yet is still waited for', () async {
    final late = FakeSourceProvider();
    final sources = SourceRegistry([late]);
    expect(sources.settled, isFalse);
    final c = open(sources, 'suwayomi:1');
    final loading = c.load();
    await _tick();
    late.controller.add([FakeSource('suwayomi:1')]);
    await loading;
    expect(sources.settled, isTrue);
    expect(c.error, isNull);
    expect(c.details, isNotNull);
  });

  test('Retry waits for the re-listing before it gives up', () async {
    final live = FakeRefreshableProvider();
    final sources = SourceRegistry([live]);
    live.controller.add([]);
    await _tick();
    final c = open(sources, 'suwayomi:1');
    await c.load();
    expect(c.error, isA<SourceUnavailable>());
    live.onRefresh = [FakeSource('suwayomi:1')];
    await c.load();
    expect(c.error, isNull);
    expect(c.details, isNotNull);
  });

  test('a failed re-listing settles again', () async {
    final live = FakeRefreshableProvider()..failWith = StateError('down');
    final sources = SourceRegistry([live]);
    live.controller.add([]);
    await _tick();
    await sources.refresh();
    expect(sources.settled, isTrue);
  });

  test('a source listed after the failure loads by itself', () async {
    final live = FakeSourceProvider();
    final sources = SourceRegistry([live]);
    live.controller.add([]);
    await _tick();
    final c = open(sources, 'suwayomi:1');
    await c.load();
    expect(c.error, isA<SourceUnavailable>());
    live.controller.add([FakeSource('suwayomi:2')]);
    await _tick();
    expect(c.error, isA<SourceUnavailable>());
    live.controller.add([FakeSource('suwayomi:1')]);
    for (var i = 0; i < 5; i++) {
      await _tick();
    }
    expect(c.error, isNull);
    expect(c.details, isNotNull);
    c.dispose();
  });

  test('a disposed screen stops waiting for its source', () async {
    final live = FakeSourceProvider();
    final sources = SourceRegistry([live]);
    live.controller.add([]);
    await _tick();
    final c = open(sources, 'suwayomi:1');
    await c.load();
    c.dispose();
    live.controller.add([FakeSource('suwayomi:1')]);
    await _tick();
    expect(c.error, isA<SourceUnavailable>());
  });
}
