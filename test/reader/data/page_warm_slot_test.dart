import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/page_list_cache.dart';
import 'package:kartka/reader/data/page_warm_slot.dart';

import '../support/fakes.dart';

ReadingProgress _at(String chapterUrl) => ReadingProgress(
  key: mangaKeyOf('fake', '/m/1'),
  chapterUrl: chapterUrl,
  chapterNumber: 2,
  page: 0,
  readAt: DateTime.utc(2026, 11, 19),
);

/// Once the details screen has loaded, the Continue chapter's page list is
/// fetched ahead, so its reader opens from the cache (971debc8).
void main() {
  late PageListCache cache;
  late FakeSource src;

  setUp(() {
    cache = PageListCache(MemoryKeyValueStore());
    src = FakeSource(
      pageMap: {'/c/1': fakePages('/c/1', 3), '/c/2': fakePages('/c/2', 4)},
    );
  });

  PageWarmSlot slot({ReadingProgress? saved, FakeDownloads? downloads}) =>
      PageWarmSlot(
        cache: cache,
        findSource: (id) async => id == src.id ? src : null,
        progress: () => FakeProgress(initial: saved),
        downloads: () => downloads,
      );

  test('the Continue chapter is fetched once details loaded', () async {
    final s = slot(saved: _at('/c/2'))..opened(mangaKeyOf('fake', '/m/1'));
    expect(src.pageCalls, isEmpty, reason: 'not beside the details fetch');
    s.loaded(mangaKeyOf('fake', '/m/1'));
    await pumpEventQueue();
    expect(src.pageCalls, ['/c/2']);
    expect(await cache.pages(src, '/c/2'), hasLength(4));
    expect(src.pageCalls, ['/c/2']);
  });

  test('nothing is fetched without progress, a source, or when the chapter '
      'is downloaded', () async {
    slot().loaded(mangaKeyOf('fake', '/m/1'));
    slot(saved: _at('/c/2')).loaded(mangaKeyOf('gone', '/m/1'));
    slot(
      saved: _at('/c/2'),
      downloads: FakeDownloads({'/c/2': fakePages('/c/2', 1)}),
    ).loaded(mangaKeyOf('fake', '/m/1'));
    await pumpEventQueue();
    expect(src.pageCalls, isEmpty);
  });

  test('a failing warm-up is swallowed', () async {
    slot(saved: _at('/c/404')).loaded(mangaKeyOf('fake', '/m/1'));
    await pumpEventQueue();
    expect(src.pageCalls, ['/c/404']);
  });

  test('with no progress, the first unread chapter is fetched', () async {
    slot().loaded(mangaKeyOf('fake', '/m/1'), firstUnread: '/c/1');
    await pumpEventQueue();
    expect(src.pageCalls, ['/c/1']);
  });

  test('progress wins over the first unread chapter', () async {
    slot(saved: _at('/c/2'))
        .loaded(mangaKeyOf('fake', '/m/1'), firstUnread: '/c/1');
    await pumpEventQueue();
    expect(src.pageCalls, ['/c/2']);
  });

  testWidgets('it shows nothing in the menu', (tester) async {
    final w = slot().build(
      tester.element(find.byType(View)),
      mangaKeyOf('fake', '/m/1'),
      const MangaDetails(sourceId: 'fake', url: '/m/1', title: 'M'),
    );
    expect(w, isA<SizedBox>());
  });
}
