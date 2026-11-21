import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/library/state/auto_shelver.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../../core/updates/backfill_fakes.dart';
import '../support/fakes.dart';

class _Facts implements ShelfFactsLookup {
  final Map<MangaKey, ShelfFacts> byKey = {};

  @override
  Future<ShelfFacts?> of(MangaKey key) async => byKey[key];
}

void main() {
  test('an entry with no stored list is fetched, then shelved', () async {
    final now = DateTime.utc(2026, 11, 21, 12);
    final kv = MemoryKeyValueStore();
    final repos = LibraryRepositories(kv, decorators: () => [], now: () => now);
    final a = entry('/a');
    await repos.library.upsert(a);
    final facts = _Facts();
    final pending = <MangaKey, ShelfFacts>{
      a.key: (newestUpload: DateTime.utc(2024, 6, 26), allRead: true),
    };
    final backfill = backfillOf(MovingChecker(pending, facts.byKey), now);
    final shelver = AutoShelver(
      repos: repos,
      facts: () => facts,
      memory: MemoryKeyValueStore(),
      local: kv,
      updater: () => null,
      clock: () => now,
      backfill: () => backfill,
    );
    expect(await shelver.run(), (finished: 1, abandoned: 0));
  });
}
