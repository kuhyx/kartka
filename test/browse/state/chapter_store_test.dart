import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/ports/browse_chapter_url_resolver.dart';
import 'package:kartka/browse/ports/browse_unread_counts.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  final src = FakeSource('mangadex');
  final key = mangaKeyOf('mangadex', '/m/1?a|b');
  ChapterStore storeWith({MemoryKeyValueStore? kv}) =>
      ChapterStore((id) => id == 'mangadex' ? src : null, kv: kv);

  setUp(src.calls.clear);

  test('loads once, then serves the cache unless refreshed', () async {
    final store = storeWith();
    expect(store.cached(key), isNull);
    await store.load(key);
    await store.load(key);
    expect(src.calls, ['chapters:/m/1?a|b']);
    await store.load(key, refresh: true);
    expect(src.calls, hasLength(2));
    expect(store.cached(key), hasLength(3));
  });

  test('unknown source throws StateError', () {
    expect(
      storeWith().load(mangaKeyOf('nope', '/x')),
      throwsA(isA<StateError>()),
    );
  });

  test('persists to the key-value store and restores after restart', () async {
    final kv = MemoryKeyValueStore();
    await storeWith(kv: kv).load(key);
    src.calls.clear();
    final fresh = storeWith(kv: kv);
    final emitted = <int?>[];
    final sub = fresh.watch(key).listen((l) => emitted.add(l?.length));
    await tick();
    expect(emitted, [null, 3]);
    expect(await fresh.load(key), hasLength(3));
    expect(src.calls, isEmpty);
    await sub.cancel();
  });

  test('a corrupt persisted entry reads as uncached', () async {
    final kv = MemoryKeyValueStore();
    await storeWith(kv: kv).load(key);
    for (final k in (await kv.entries()).keys) {
      await kv.set(k, '{not json');
    }
    final fresh = storeWith(kv: kv);
    expect(await fresh.load(key), hasLength(3));
    expect(src.calls, hasLength(2));
  });

  test('unread counts: null until loaded, then chapters minus read', () async {
    final store = storeWith();
    final progress = FakeProgress();
    final counts = <int?>[];
    final sub = BrowseUnreadCounts(
      store,
      progress,
    ).watch(key).listen(counts.add);
    await tick();
    await store.load(key);
    await progress.markRead(key, '/c/1');
    await tick();
    await progress.record(
      ReadingProgress(
        key: key,
        chapterUrl: '/c/3',
        chapterNumber: 3,
        page: 0,
        readAt: DateTime.utc(2026),
      ),
    );
    await tick();
    expect(counts, [null, 3, 2, 0]);
    await sub.cancel();
  });

  test('resolver maps a chapter number to its url', () async {
    final resolver = BrowseChapterUrlResolver(storeWith());
    expect(await resolver.resolve(key, 2), '/c/2');
    expect(await resolver.resolve(key, 9), isNull);
    expect(await resolver.resolve(mangaKeyOf('nope', '/x'), 1), isNull);
    expect(await resolver.numberOf(key, '/c/1'), 1);
    expect(await resolver.numberOf(key, '/c/none'), isNull);
    expect(await resolver.numberOf(mangaKeyOf('nope', '/x'), '/c/1'), isNull);
  });
}
