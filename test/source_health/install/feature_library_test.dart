import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/source_health/source_health_feature.dart';

void main() {
  test('the library source ids come from the library part, or none', () async {
    final bare = KartkaRegistry.build(memoryPlatform(), const []);
    expect(await librarySourceIds(bare).first, isEmpty);

    final repos = LibraryRepositories(
      MemoryKeyValueStore(),
      decorators: () => const [],
    );
    for (final (source, url) in [('suwayomi:491', '/a'), ('mangadex', '/b')]) {
      await repos.library.upsert(
        LibraryEntry(
          key: mangaKeyOf(source, url),
          sourceId: source,
          mangaUrl: url,
          title: url,
          addedAt: DateTime.utc(2025),
          updatedAt: DateTime.utc(2025),
        ),
      );
    }
    final registry = KartkaRegistry.build(memoryPlatform(), [
      (_) => KartkaFeature(id: 'library', services: [repos]),
    ]);
    expect(await librarySourceIds(registry).first, {
      'suwayomi:491',
      'mangadex',
    });
  });
}
