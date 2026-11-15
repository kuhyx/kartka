import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/updates/data/update_feed.dart';
import 'package:kartka/updates/state/updates_deps.dart';
import 'package:kartka/updates/ui/update_tile.dart';
import 'package:kartka/updates/ui/updates_screen.dart';

import '../../helpers/fake_updater.dart';
import 'fit_harness.dart';

/// Updates with 40 manga, two new chapters each: more than one screen.
Future<FitScreen> updatesFit() async {
  final kv = MemoryKeyValueStore();
  final repos = LibraryRepositories(kv, decorators: () => []);
  final feed = UpdateFeed(kv, inLibrary: (_) async => true);
  for (var i = 0; i < 40; i++) {
    final key = mangaKeyOf('mangadex', '/m/$i');
    await repos.library.upsert(
      LibraryEntry(
        key: key,
        sourceId: 'mangadex',
        mangaUrl: '/m/$i',
        title: 'Manga number $i',
        addedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    await feed.record(key, [
      for (final n in [1, 2])
        ChapterInfo(url: '/m/$i/$n', name: 'Ch. $n', number: n.toDouble()),
    ]);
  }
  final deps = UpdatesDeps(
    feed: feed,
    library: repos.library,
    progress: repos.progress,
    updater: FakeUpdater(),
  );
  return FitScreen(
    tab: KartkaTab.updates,
    screen: (_) => UpdatesScreen(deps: deps),
    tiles: find.byType(UpdateTile),
  );
}
