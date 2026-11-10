import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/browse/state/refresh_outcome.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

void main() {
  final when = DateTime.utc(2026, 10, 24, 12);
  late FakeSource src;
  late FakeLibrary library;
  late FakeProgress progress;
  late FakeDownloads downloads;
  late FakeSourceProvider provider;
  late BrowseDeps deps;

  setUp(() {
    src = FakeSource('mangadex');
    library = FakeLibrary();
    progress = FakeProgress();
    downloads = FakeDownloads();
    provider = FakeSourceProvider();
    final sources = SourceRegistry([
      StaticSourceProvider([src]),
      provider,
    ]);
    deps = BrowseDeps(
      sources: sources,
      languages: BrowseLanguageStore(MemoryKeyValueStore()),
      chapters: ChapterStore(sources.byId),
      library: library,
      progress: progress,
      downloads: downloads,
      clock: () => when,
    );
  });

  MangaDetailController ctl([String id = 'mangadex']) =>
      MangaDetailController(deps, sourceId: id, mangaUrl: '/m/1');

  test('loads details and chapters oldest-first', () async {
    final c = ctl();
    await c.load();
    expect(c.loading, isFalse);
    expect(c.details?.title, 'Detail title');
    expect(c.chapters.map((ch) => ch.url), ['/c/1', '/c/2', '/c/3']);
    expect(c.key, mangaKeyOf('mangadex', '/m/1'));
  });

  test('refresh after a failed first load that fails again', () async {
    src.failWith = StateError('down');
    final c = ctl();
    await c.load();
    final outcome = await c.refresh();
    expect(outcome, isA<RefreshFailed>());
    expect(c.details, isNull);
  });

  test('a failed load is logged as details.load, URLs stripped', () async {
    final log = DiagnosticsLog(MemoryBlobStore());
    deps = BrowseDeps(
      sources: deps.sources,
      languages: deps.languages,
      chapters: deps.chapters,
      library: library,
      progress: progress,
      downloads: downloads,
      clock: () => when,
      diagnostics: log,
    );
    src.failWith = StateError('down https://h.test/x?auth=SECRET');
    final c = ctl();
    await c.load();
    final e = (await log.entries()).single;
    expect(e.kind, 'details.load');
    expect(e.sourceId, 'mangadex');
    expect(e.error, 'Bad state: down <url>');
    expect(e.stack, isNotEmpty);
    src.failWith = null;
    await c.refresh();
    await c.load();
    expect(await log.entries(), hasLength(1));
  });

  test('a source failure becomes error', () async {
    src.failWith = StateError('down');
    final c = ctl();
    await c.load();
    expect(c.error, isA<StateError>());
    expect(c.details, isNull);
  });

  test('waits for a runtime source to appear', () async {
    final c = ctl('plugin:late');
    final done = c.load();
    await Future<void>.delayed(Duration.zero);
    provider.controller.add([FakeSource('plugin:late')]);
    await done;
    expect(c.details, isNotNull);
  });

  test('gives up on a source that never appears', () async {
    final c = MangaDetailController(
      deps,
      sourceId: 'plugin:never',
      mangaUrl: '/m/1',
      sourceWait: const Duration(milliseconds: 10),
    );
    await c.load();
    expect(c.error, isA<SourceUnavailable>());
    expect('${c.error}', contains('plugin:never'));
  });

  test('retry after "source unavailable" re-fetches the sources', () async {
    final lazy = FakeRefreshableProvider();
    final sources = SourceRegistry([lazy]);
    final c = MangaDetailController(
      BrowseDeps(
        sources: sources,
        languages: BrowseLanguageStore(MemoryKeyValueStore()),
        chapters: ChapterStore(sources.byId),
        library: library,
        progress: progress,
        clock: () => when,
      ),
      sourceId: 'suwayomi:1',
      mangaUrl: '/m/1',
      sourceWait: const Duration(milliseconds: 10),
    );
    await c.load();
    expect(c.error, isA<SourceUnavailable>());
    expect(lazy.refreshes, 0, reason: 'a first load does not refresh');
    lazy.onRefresh = [FakeSource('suwayomi:1')];
    await c.load();
    expect(lazy.refreshes, 1);
    expect(c.error, isNull);
    expect(c.details, isNotNull);
    await sources.dispose();
  });

  test('library add uses the clock, remove tombstones', () async {
    final c = ctl();
    final states = <bool>[];
    final sub = c.inLibrary().listen(states.add);
    await c.setInLibrary(add: true); // Before load: no details, no-op.
    await c.load();
    await c.setInLibrary(add: true);
    final entry = library.entries[c.key]!;
    expect(entry.addedAt, when);
    expect(entry.title, 'Detail title');
    await c.setInLibrary(add: false);
    await Future<void>.delayed(Duration.zero);
    expect(states, [false, true, false]);
    await sub.cancel();
  });

  test('mark read and unread', () async {
    final c = ctl();
    await c.load();
    await c.setRead(c.chapters.first, read: true);
    expect(readUrls(c.chapters, await c.readMarks().first), {'/c/1'});
    await c.setRead(c.chapters.first, read: false);
    expect(readUrls(c.chapters, await c.readMarks().first), isEmpty);
    expect(await c.progress().first, isNull);
    await progress.record(
      ReadingProgress(
        key: c.key,
        chapterUrl: '/c/3',
        chapterNumber: 3,
        page: 0,
        readAt: when,
      ),
    );
    // Progress past /c/2 reads it; /c/1 stays unread because of its
    // tombstone; /c/3 is only opened, so it is not read yet.
    expect(readUrls(c.chapters, await c.readMarks().first), {'/c/2'});
  });

  test('download queues each chapter; no-op without downloads', () async {
    final c = ctl();
    await c.load();
    await c.download(c.chapters.skip(1));
    expect(downloads.enqueued, ['/c/2', '/c/3']);
    final bare = MangaDetailController(
      BrowseDeps(
        sources: deps.sources,
        languages: deps.languages,
        chapters: deps.chapters,
        library: library,
        progress: progress,
      ),
      sourceId: 'mangadex',
      mangaUrl: '/m/1',
    );
    await bare.download(c.chapters);
    expect(downloads.enqueued, hasLength(2));
    c.dispose();
    await bare.load(); // Still fine after another controller's dispose.
  });

  test('notifications after dispose are swallowed', () async {
    final c = ctl();
    final pending = c.load();
    c.dispose();
    await pending;
  });
}
