import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/store_chapter_update_checker.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

List<ChapterInfo> _upTo(int last) => [
  for (var n = last; n >= 1; n--)
    ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble()),
];

void main() {
  final key = mangaKeyOf('mangadex', '/m/1?a=b');
  late FakeSource src;
  late MemoryKeyValueStore kv;
  late ChapterStore store;
  late StoreChapterUpdateChecker checker;

  ChapterStore storeOn(MemoryKeyValueStore kv) =>
      ChapterStore((id) => id == 'mangadex' ? src : null, kv: kv);

  int fetches() => src.calls.where((c) => c.startsWith('chapters')).length;

  setUp(() {
    src = FakeSource('mangadex');
    kv = MemoryKeyValueStore();
    store = storeOn(kv);
    checker = StoreChapterUpdateChecker(store);
  });

  test('nothing stored: the fetch is the baseline, nothing new', () async {
    final r = await checker.check(key);
    expect(r, isA<UpdateFound>());
    final found = r as UpdateFound;
    expect(found.key, key);
    expect(found.firstCheck, isTrue);
    expect(found.added, isEmpty);
    expect(found.chapters, hasLength(3));
    expect(store.cached(key), hasLength(3));
  });

  test('diffs against the stored list, new ones oldest first', () async {
    await store.load(key);
    src.chapterList = _upTo(5);
    final found = await checker.check(key) as UpdateFound;
    expect(found.firstCheck, isFalse);
    expect(found.added.map((c) => c.url), ['/c/4', '/c/5']);
    expect(found.chapters, hasLength(5));
    // Persisted: a restarted store sees the new list without fetching.
    src.calls.clear();
    expect(await storeOn(kv).stored(key), hasLength(5));
    expect(fetches(), 0);
  });

  test('nothing new', () async {
    await store.load(key);
    final found = await checker.check(key) as UpdateFound;
    expect(found.added, isEmpty);
    expect(found.firstCheck, isFalse);
  });

  test('the baseline survives a restart (restored from kv)', () async {
    await store.load(key);
    src.chapterList = _upTo(4);
    final restarted = StoreChapterUpdateChecker(storeOn(kv));
    final found = await restarted.check(key) as UpdateFound;
    expect(found.added.map((c) => c.url), ['/c/4']);
  });

  test('a failing fetch is an UpdateFailed; the stored list stays', () async {
    await store.load(key);
    final boom = StateError('down');
    src.failWith = boom;
    final r = await checker.check(key);
    expect(r, isA<UpdateFailed>());
    expect((r as UpdateFailed).error, same(boom));
    expect(r.key, key);
    expect(store.cached(key), hasLength(3));
  });

  test('an unknown source is an UpdateFailed, never a throw', () async {
    final r = await checker.check(mangaKeyOf('nope', '/x'));
    expect((r as UpdateFailed).error, isA<StateError>());
  });

  test('concurrent checks of one manga share one fetch', () async {
    await store.load(key);
    src
      ..calls.clear()
      ..chapterList = _upTo(4);
    final results = await Future.wait([checker.check(key), checker.check(key)]);
    expect(fetches(), 1);
    expect(results.first, same(results.last));
    expect((results.first as UpdateFound).added, hasLength(1));
  });

  test('a finished check does not block the next one', () async {
    await checker.check(key);
    await checker.check(key);
    expect(fetches(), 2);
  });

  test('different manga are checked independently', () async {
    final other = mangaKeyOf('mangadex', '/m/2');
    await Future.wait([checker.check(key), checker.check(other)]);
    expect(src.calls, containsAll(['chapters:/m/1?a=b', 'chapters:/m/2']));
  });
}
