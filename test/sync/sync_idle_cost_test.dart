import 'package:crdt_sync/crdt_sync.dart' show Hlc;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_shadow.dart';

import 'fakes.dart';

/// Counts the writes that reach the store.
class CountingStore implements KeyValueStore {
  final inner = MemoryKeyValueStore();
  final writes = <String>[];

  @override
  Future<String?> get(String key) => inner.get(key);

  @override
  Future<void> set(String key, String value) {
    writes.add(key);
    return inner.set(key, value);
  }

  @override
  Future<void> remove(String key) {
    writes.add(key);
    return inner.remove(key);
  }

  @override
  Future<Map<String, String>> entries({String prefix = ''}) =>
      inner.entries(prefix: prefix);
}

Node _title(String title, Hlc at) => {
  'title': title,
  'hlc': {'title': at.toStr()},
};

void main() {
  late InMemoryRtdb db;
  late CountingStore kv;
  late TestClock clock;
  setUp(() {
    db = InMemoryRtdb();
    kv = CountingStore();
    clock = TestClock();
  });

  test('a poll that finds nothing new writes nothing', () async {
    final a = await engineFor('dev-a', db);
    final counted = await engineFor('dev-b', db, kv: kv, clock: clock);
    await a.write('library/h1', _title('One', a.tick()));
    await counted.poll();
    kv.writes.clear();
    for (var i = 0; i < 5; i++) {
      clock.advance(const Duration(seconds: 5));
      await counted.poll();
    }
    expect(kv.writes, isEmpty, reason: 'no peers, hlc or lastSync rewrite');
    expect(counted.status.lastSync, clock.now, reason: 'kept in memory');
  });

  test('lastSync is persisted with real changes and on flush', () async {
    final a = await engineFor('dev-a', db);
    final b = await engineFor('dev-b', db, kv: kv, clock: clock);
    await a.write('library/h1', _title('One', a.tick()));
    await b.poll();
    final first = clock.now;
    expect((await SyncShadow.load(kv)).lastSync, first);
    clock.advance(const Duration(minutes: 1));
    await b.poll();
    expect((await SyncShadow.load(kv)).lastSync, first, reason: 'lazy');
    await b.flush();
    expect((await SyncShadow.load(kv)).lastSync, clock.now);
    kv.writes.clear();
    await b.flush();
    expect(kv.writes, isEmpty, reason: 'already persisted');
  });

  test('a changed peer revision is persisted', () async {
    final a = await engineFor('dev-a', db);
    final b = await engineFor('dev-b', db, kv: kv, clock: clock);
    await a.write('library/h1', _title('One', a.tick()));
    await b.poll();
    kv.writes.clear();
    await a.write('library/h1', _title('Two', a.tick()));
    await b.poll();
    expect(kv.writes, contains('sync.peers'));
    expect((await SyncShadow.load(kv)).peers, {'dev-a': '2'});
  });
}
