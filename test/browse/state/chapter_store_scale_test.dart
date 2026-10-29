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

void main() {
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
    final store = ChapterStore((_) => FakeSource('mangadex'));
    final a = <int?>[];
    final b = <int?>[];
    final subA = store.watch(_key(1)).listen((l) => a.add(l?.length));
    final subB = store.watch(_key(1)).listen((l) => b.add(l?.length));
    return Future(() async {
      await store.load(_key(1));
      await subA.cancel();
      await store.load(_key(1), refresh: true);
      await pumpEventQueue();
      expect(a, [null, 3]);
      expect(b, [null, 3, 3]);
      await subB.cancel();
    });
  });
}
