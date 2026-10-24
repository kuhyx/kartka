import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/suwayomi_feature.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source_provider.dart';

void main() {
  test('the registry entry looks titles up in the library', () async {
    final repos = LibraryRepositories(
      MemoryKeyValueStore(),
      decorators: () => [],
    );
    final registry = KartkaRegistry.build(memoryPlatform(), [
      suwayomiFeature,
      (_) => KartkaFeature(id: 'library', services: [repos]),
    ]);
    expect(registry.features.first.id, 'source-suwayomi');
    const key = 'suwayomi:1|/manga/x';
    final at = DateTime.utc(2026);
    await repos.library.upsert(
      LibraryEntry(
        key: key,
        sourceId: 'suwayomi:1',
        mangaUrl: '/manga/x',
        title: 'X',
        addedAt: at,
        updatedAt: at,
      ),
    );
    expect(await libraryTitle(repos, key), 'X');
    expect(await libraryTitle(repos, 'missing'), isNull);
    expect(await libraryTitle(null, key), isNull);
    final provider = registry.all<SuwayomiSourceProvider>().single;
    expect(await provider.titleOf!(key), 'X');
  });
}
