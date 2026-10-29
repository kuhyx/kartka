import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/store_chapter_update_checker.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

ChapterInfo _ch(int n) =>
    ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble());

void main() {
  final key = mangaKeyOf('mangadex', '/m/1');
  late FakeSource src;
  late List<String> seen;
  ChapterStore storeWith(MemoryKeyValueStore kv) => ChapterStore(
    (id) => id == 'mangadex' ? src : null,
    kv: kv,
    onAdded: (k, added) => seen.add('$k ${added.map((c) => c.url).join(',')}'),
  );

  setUp(() {
    src = FakeSource('mangadex', chapters: [_ch(2), _ch(1)]);
    seen = [];
  });

  test('the first fetch is a baseline: nothing reported', () async {
    final store = storeWith(MemoryKeyValueStore());
    await store.load(key);
    await store.load(key, refresh: true);
    expect(seen, isEmpty);
  });

  test('a detail-style refresh reports grown chapters, oldest first', () async {
    final store = storeWith(MemoryKeyValueStore());
    await store.load(key);
    src.chapterList = [_ch(4), _ch(3), _ch(2), _ch(1)];
    await store.load(key, refresh: true);
    expect(seen, ['$key /c/3,/c/4']);
  });

  test('after a restart the kv copy is the baseline', () async {
    final kv = MemoryKeyValueStore();
    await storeWith(kv).load(key);
    src.chapterList = [_ch(3), _ch(2), _ch(1)];
    await storeWith(kv).load(key, refresh: true);
    expect(seen, ['$key /c/3']);
  });

  test('the update checker path reports through the same hook', () async {
    final store = storeWith(MemoryKeyValueStore());
    final checker = StoreChapterUpdateChecker(store);
    await checker.check(key);
    src.chapterList = [_ch(3), _ch(2), _ch(1)];
    await checker.check(key);
    expect(seen, ['$key /c/3']);
  });

  test('an unchanged or shrunk list reports nothing', () async {
    final store = storeWith(MemoryKeyValueStore());
    await store.load(key);
    await store.load(key, refresh: true);
    src.chapterList = [_ch(1)];
    await store.load(key, refresh: true);
    expect(seen, isEmpty);
  });
}
