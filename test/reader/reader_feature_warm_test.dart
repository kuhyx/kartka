import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/reader/reader_feature.dart';

import 'support/fakes.dart';

/// The reader registers the slot that fetches the Continue chapter's page
/// list once a manga's details load (971debc8).
void main() {
  test('a loaded details screen warms its Continue chapter', () async {
    final kv = MemoryKeyValueStore();
    final repos = LibraryRepositories(kv, decorators: () => []);
    final source = FakeSource(pageMap: {'/c/2': fakePages('/c/2', 2)});
    final registry = KartkaRegistry.build(memoryPlatform(kv: kv), [
      readerFeature,
      (env) => KartkaFeature(
        id: 'test',
        services: [
          StaticSourceProvider([source]),
          repos,
        ],
      ),
    ]);
    final key = mangaKeyOf('fake', '/m/1');
    await repos.progress.record(
      ReadingProgress(
        key: key,
        chapterUrl: '/c/2',
        chapterNumber: 2,
        page: 0,
        readAt: DateTime.utc(2026, 11, 19),
      ),
    );
    registry.all<MangaDetailSlot>().single.loaded(key);
    await pumpEventQueue();
    expect(source.pageCalls, ['/c/2']);
  });
}
