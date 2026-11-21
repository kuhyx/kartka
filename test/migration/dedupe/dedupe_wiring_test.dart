import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/core/updates/chapter_backfill.dart';
import 'package:kartka/library/library_feature.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/migration/dedupe/dedupe_wiring.dart';
import 'package:kartka/migration/dedupe/library_deduper.dart';
import 'package:kartka/migration/migration_feature.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:material_ui/material_ui.dart';

import '../fakes.dart';
import 'dedupe_fakes.dart';

class _Health implements SourceHealthLookup {
  new(this.stream);

  final Stream<Map<String, SourceHealthSummary>> stream;

  @override
  Stream<Map<String, SourceHealthSummary>> watch() => stream;

  @override
  Widget? buildBadge(BuildContext c, String id, SourceHealthSummary? s) => null;
}

/// A provider whose re-list never completes (a server that hangs).
class _Hung implements RefreshableSourceProvider {
  @override
  Stream<List<MangaSource>> watch() => Stream.value(const []);

  @override
  Future<void> refresh() => Completer<void>().future;
}

void main() {
  test('ranks: the first emission; null without a lookup or in time', () async {
    final ranks = {'a': keepAt(1)};
    expect(await healthRanks(_Health(Stream.value(ranks))), ranks);
    expect(await healthRanks(null), isNull);
    final never = StreamController<Map<String, SourceHealthSummary>>();
    expect(
      await healthRanks(_Health(never.stream), timeout: Duration.zero),
      isNull,
    );
  });

  test(
    'installed ids do not wait past the timeout for a hung re-list',
    () async {
      final registry = KartkaRegistry([
        KartkaFeature(
          id: 'p',
          services: [
            _Hung(),
            StaticSourceProvider([ScriptedSource('fine')]),
          ],
        ),
      ]);
      expect(
        await installedSourceIds(
          registry,
          timeout: const Duration(milliseconds: 20),
        ),
        {'fine'},
      );
    },
  );

  test('the migration part registers a library start task', () async {
    final facts = FakeDupeFacts();
    final registry = KartkaRegistry.build(memoryPlatform(), [
      libraryFeature,
      migrationFeature,
      (_) => KartkaFeature(id: 'browse', services: [facts]),
    ]);
    final deduper = registry.maybe<LibraryStartTask>()! as LibraryDeduper;
    expect(deduper.facts(), same(facts));
    expect(deduper.updater(), isNull);
    expect(deduper.backfill(), same(registry.maybe<ChapterBackfill>()));
    expect(deduper.backfill(), isNotNull);
    expect(await deduper.health(), isNull);
    expect(await deduper.installed(), isEmpty);
    expect(deduper.deps().library, isNotNull);
    expect(await deduper.run(), 0);
  });
}
