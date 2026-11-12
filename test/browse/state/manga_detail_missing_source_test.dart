import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/browse/state/refresh_outcome.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/core/source/unknown_source_error.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

/// Answers every check with a missing source, as `ChapterStore` does once
/// the source is uninstalled after the details loaded.
class _Gone implements ChapterUpdateChecker {
  @override
  Future<UpdateResult> check(MangaKey key) async =>
      UpdateFailed(key, UnknownSourceError(splitMangaKey(key).$1));
}

void main() {
  late DiagnosticsLog log;
  late SourceRegistry sources;

  setUp(() {
    log = DiagnosticsLog(MemoryBlobStore());
    sources = SourceRegistry([
      StaticSourceProvider([FakeSource('mangadex')]),
    ]);
  });

  BrowseDeps deps({ChapterUpdateChecker? updates}) => BrowseDeps(
    sources: sources,
    languages: BrowseLanguageStore(MemoryKeyValueStore()),
    chapters: ChapterStore(sources.byId),
    library: FakeLibrary(),
    progress: FakeProgress(),
    clock: () => DateTime.utc(2026, 11, 6),
    diagnostics: log,
    updates: updates,
  );

  test('a source that is not installed shows, but is not reported', () async {
    final c = MangaDetailController(
      deps(),
      sourceId: 'sy-builtin:6901',
      mangaUrl: '/m/1',
      sourceWait: const Duration(milliseconds: 10),
    );
    await c.load();
    expect(c.error, isA<SourceUnavailable>());
    expect(await c.refresh(), isA<RefreshFailed>());
    expect(await log.entries(), isEmpty);
  });

  test('a refresh after the source went away is not reported', () async {
    final c = MangaDetailController(
      deps(updates: _Gone()),
      sourceId: 'mangadex',
      mangaUrl: '/m/1',
    );
    await c.load();
    expect(c.details, isNotNull);
    final outcome = await c.refresh();
    expect(outcome, isA<RefreshFailed>());
    expect(refreshMessage(outcome), 'Source mangadex is not installed');
    expect(await log.entries(), isEmpty);
  });
}
