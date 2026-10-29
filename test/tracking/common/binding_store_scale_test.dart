import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/track_binding.dart';

/// The phone's library size when the cold-start freeze was measured.
const _n = 775;

MangaKey _key(int i) => mangaKeyOf('mangadex', '/m/$i');

/// Counts full scans (`entries`), the cost each per-key read used to pay.
class _CountingKv extends MemoryKeyValueStore {
  int scans = 0;

  @override
  Future<Map<String, String>> entries({String prefix = ''}) {
    scans++;
    return super.entries(prefix: prefix);
  }
}

void main() {
  test('N watchers cost one scan, a put re-emits only its key', () async {
    final kv = _CountingKv();
    final seed = KvBindingStore(kv);
    for (var i = 0; i < _n; i += 2) {
      await seed.put(
        TrackBinding(key: _key(i), service: 'anilist', remoteId: '$i'),
      );
    }
    final store = KvBindingStore(kv);
    kv.scans = 0;
    final seen = <MangaKey, List<List<TrackBinding>>>{};
    final subs = [
      for (var i = 0; i < _n; i++)
        store.watch(_key(i)).listen((b) => (seen[_key(i)] ??= []).add(b)),
    ];
    await pumpEventQueue();
    expect(seen, hasLength(_n));
    expect(seen[_key(2)]!.single.single.remoteId, '2');
    expect(seen[_key(3)]!.single, isEmpty);
    expect(kv.scans, 1, reason: 'one shared load, not one per watcher');

    await store.put(TrackBinding(key: _key(3), service: 'mal', remoteId: 'x'));
    await pumpEventQueue();
    expect(seen[_key(3)]!.last.single.remoteId, 'x');
    expect(seen[_key(5)], hasLength(1), reason: 'other keys stay quiet');
    expect(kv.scans, 1);
    expect((await store.all()).length, _n ~/ 2 + 2);

    await store.remove(_key(2), 'anilist');
    await pumpEventQueue();
    expect(seen[_key(2)]!.last, isEmpty);
    expect(await store.all(), hasLength(_n ~/ 2 + 1));
    for (final s in subs) {
      unawaited(s.cancel());
    }
  });

  test('a corrupt stored binding is skipped', () async {
    final kv = MemoryKeyValueStore();
    await kv.set('tracking.binding.${mangaKeyHash(_key(1))}.mal', '{bad');
    final store = KvBindingStore(kv);
    expect(await store.all(), isEmpty);
    expect(await store.watch(_key(1)).first, isEmpty);
  });
}
