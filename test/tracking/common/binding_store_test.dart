import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/track_binding.dart';

import '../fakes.dart';

const _k = 'mangadex|/manga/abc';
const _b = TrackBinding(key: _k, service: 'anilist', remoteId: '30104');

void main() {
  late MemoryKeyValueStore kv;
  late KvBindingStore store;

  setUp(() {
    kv = MemoryKeyValueStore();
    store = KvBindingStore(kv);
  });

  test('TrackBinding JSON round-trips and compares by value', () {
    const b = TrackBinding(
      key: _k,
      service: 'mal',
      remoteId: '7',
      lastPushedChapter: 3,
    );
    expect(TrackBinding.fromJson(b.toJson()), b);
    expect(TrackBinding.fromJson(_b.toJson()), _b);
    expect(b.hashCode, TrackBinding.fromJson(b.toJson()).hashCode);
    expect(b.toString(), contains('mal'));
    expect(b.copyWith(lastPushedChapter: 9).lastPushedChapter, 9);
    expect(b.copyWith().remoteId, '7');
  });

  test('put stores under the hashed key and all() returns it', () async {
    await store.put(_b);
    expect(
      (await kv.entries()).keys.single,
      'tracking.binding.${mangaKeyHash(_k)}.anilist',
    );
    expect(await store.all(), [_b]);
  });

  test('put never lowers lastPushedChapter for the same remote id', () async {
    await store.put(_b.copyWith(lastPushedChapter: 10));
    await store.put(_b.copyWith(lastPushedChapter: 4));
    expect((await store.all()).single.lastPushedChapter, 10);
    await store.put(_b);
    expect((await store.all()).single.lastPushedChapter, 10);
  });

  test('rebinding to another remote id resets lastPushedChapter', () async {
    await store.put(_b.copyWith(lastPushedChapter: 10));
    const other = TrackBinding(key: _k, service: 'anilist', remoteId: '1');
    await store.put(other);
    expect((await store.all()).single, other);
  });

  test('watch emits the current bindings, then every change', () async {
    final seen = <List<TrackBinding>>[];
    final sub = store.watch(_k).listen(seen.add);
    await pumpEvents();
    await store.put(_b);
    await store.put(
      const TrackBinding(key: 'other', service: 's', remoteId: '1'),
    );
    await pumpEvents();
    await store.remove(_k, 'anilist');
    await pumpEvents();
    await sub.cancel();
    expect(seen, [
      <TrackBinding>[],
      [_b],
      <TrackBinding>[],
    ]);
  });

  test('corrupt entries are skipped', () async {
    await kv.set('tracking.binding.x.anilist', 'nope');
    await kv.set('tracking.binding.y.anilist', '[1]');
    expect(await store.all(), isEmpty);
  });
}
