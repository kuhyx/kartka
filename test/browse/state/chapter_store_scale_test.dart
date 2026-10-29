import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

/// The phone's library size when the cold-start freeze was measured.
const _n = 775;

MangaKey _key(int i) => mangaKeyOf('mangadex', '/m/$i');

String _stored(int i) => jsonEncode([
  ChapterInfo(url: '/c$i', name: 'Chapter $i', number: 1).toJson(),
]);

/// Counts writes: each one is a whole-list `jsonEncode` on the UI isolate.
class _CountingKv extends MemoryKeyValueStore {
  int sets = 0;

  @override
  Future<void> set(String key, String value) {
    sets++;
    return super.set(key, value);
  }
}

void main() {
  test(
    'a refresh that finds the same list writes and notifies nothing',
    () async {
      final kv = _CountingKv();
      final src = FakeSource('mangadex');
      final store = ChapterStore((_) => src, kv: kv, onAdded: (_, _) {});
      final first = await store.load(_key(1));
      expect(kv.sets, 1);
      final sub = store.watch(_key(1)).listen((_) {});
      store.callbacks = 0;
      expect(await store.load(_key(1), refresh: true), same(first));
      expect(kv.sets, 1, reason: 'update-all: most manga did not change');
      expect(store.callbacks, 0);
      src.chapterList = [...src.chapterList.reversed];
      await store.load(_key(1), refresh: true);
      expect(kv.sets, 2);
      expect(store.callbacks, 1);
      await sub.cancel();
    },
  );

  test('N watchers restoring N lists cost O(N) callbacks, not N²', () async {
    final kv = MemoryKeyValueStore({
      for (var i = 0; i < _n; i++)
        'browse.chapters.${mangaKeyHash(_key(i))}': _stored(i),
    });
    final store = ChapterStore((_) => FakeSource('mangadex'), kv: kv);
    final seen = <MangaKey, String>{};
    final subs = [
      for (var i = 0; i < _n; i++)
        store.watch(_key(i)).listen((l) {
          if (l != null) seen[_key(i)] = l.first.url;
        }),
    ];
    // The burst is large enough to decode in a background isolate.
    while (seen.length < _n) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(seen[_key(7)], '/c7', reason: 'each watcher gets its own list');
    expect(store.callbacks, lessThanOrEqualTo(2 * _n));

    store.callbacks = 0;
    await store.load(_key(3), refresh: true);
    expect(store.callbacks, 1, reason: 'a fetch tells only its watcher');
    expect(seen[_key(3)], '/c/3', reason: 'the fetched list');

    for (final s in subs) {
      unawaited(s.cancel());
    }
    await pumpEventQueue();
    store.callbacks = 0;
    await store.load(_key(4), refresh: true);
    expect(store.callbacks, 0, reason: 'cancelled watchers are gone');
  });

  test('two watchers of one key both hear, one cancel keeps the other', () {
    final src = FakeSource('mangadex');
    final store = ChapterStore((_) => src);
    final a = <int?>[];
    final b = <int?>[];
    final subA = store.watch(_key(1)).listen((l) => a.add(l?.length));
    final subB = store.watch(_key(1)).listen((l) => b.add(l?.length));
    return Future(() async {
      await store.load(_key(1));
      await subA.cancel();
      src.chapterList = src.chapterList.skip(1).toList();
      await store.load(_key(1), refresh: true);
      await pumpEventQueue();
      expect(a, [null, 3]);
      expect(b, [null, 3, 2]);
      await subB.cancel();
    });
  });
}
