import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/decorators/synced_bindings.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/track_binding.dart';

import '../fakes.dart';

final MangaKey _key = mangaKeyOf('mangadex', '/manga/1');

TrackBinding _b(String id, [int? chapters]) => TrackBinding(
  key: _key,
  service: 'anilist',
  remoteId: id,
  lastPushedChapter: chapters,
);

Future<(SyncEngine, SyncedBindingStore)> _device(
  String id,
  InMemoryRtdb db,
) async {
  final engine = await engineFor(id, db);
  final store = SyncBindingDecorator(() => Future.value(engine))
      .decorate(KvBindingStore(MemoryKeyValueStore()));
  return (engine, store as SyncedBindingStore);
}

Future<void> _poll(SyncEngine e, SyncedBindingStore s) async {
  await e.poll();
  await pumpEventQueue();
  await s.settled;
}

void main() {
  late InMemoryRtdb db;
  setUp(() => db = InMemoryRtdb());

  test('a binding made on one device is emitted live on the other', () async {
    final (ea, a) = await _device('dev-a', db);
    final (eb, b) = await _device('dev-b', db);
    final seen = <List<TrackBinding>>[];
    final sub = b.watch(_key).listen(seen.add);
    await a.put(_b('21', 3));
    await _poll(eb, b);
    await pumpEventQueue();
    expect(seen.last, [_b('21', 3)]);
    expect(await b.all(), [_b('21', 3)]);
    await sub.cancel();
    await ea.dispose();
  });

  test('pushed chapters max-merge and never decrease', () async {
    final (_, a) = await _device('dev-a', db);
    final (eb, b) = await _device('dev-b', db);
    await a.put(_b('21', 7));
    await _poll(eb, b);
    await b.put(_b('21', 5));
    final remote =
        ((db.tree['trackers']! as Map)[mangaKeyHash(_key)] as Map)['anilist']
            as Map;
    expect(remote['lastPushedChapter'], 7);
    expect(remote['remoteId'], '21');
  });

  test('unbinding reaches the other device; a rebind wins after', () async {
    final (ea, a) = await _device('dev-a', db);
    final (eb, b) = await _device('dev-b', db);
    await a.put(_b('21', 4));
    await _poll(eb, b);
    await a.remove(_key, 'anilist');
    await _poll(eb, b);
    expect(await b.all(), isEmpty);
    await b.put(_b('99'));
    await _poll(ea, a);
    expect(await a.all(), [_b('99')]);
  });

  test('a store whose engine failed still works locally', () async {
    final store = SyncBindingDecorator(
      () => Future<SyncEngine>.error(StateError('x')),
    ).decorate(KvBindingStore(MemoryKeyValueStore()));
    await store.put(_b('1', 2));
    expect(await store.all(), [_b('1', 2)]);
    await store.remove(_key, 'anilist');
    expect(await store.all(), isEmpty);
  });

  test('malformed tracker nodes are ignored', () async {
    final (eb, b) = await _device('dev-b', db);
    await db.patch({
      'trackers/h/anilist': {'remoteId': '1'},
      'revs/dev-z': '1',
    });
    await _poll(eb, b);
    expect(await b.all(), isEmpty);
  });
}
