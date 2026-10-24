import 'package:crdt_sync/crdt_sync.dart' show FirebaseSyncError, Hlc;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_shadow.dart';
import 'package:kartka/sync/sync_status.dart';

import 'fakes.dart';

Node _title(String title, Hlc at) => {
  'title': title,
  'hlc': {'title': at.toStr()},
};

void main() {
  late InMemoryRtdb db;
  setUp(() => db = InMemoryRtdb());

  test('signed out: the write is kept locally and marked for push', () async {
    final a = await engineFor('dev-a', db, signedIn: false);
    await a.write('library/h1', _title('One', a.tick()));
    expect(a.shadow.dirty, {'library/h1'});
    expect(a.status.phase, SyncPhase.signedOut);
    expect(db.writes, 0);
  });

  test('write-through pushes the node and bumps revs atomically', () async {
    final a = await engineFor('dev-a', db);
    await a.write('library/h1', _title('One', a.tick()));
    expect((db.tree['library']! as Map)['h1'], containsPair('title', 'One'));
    expect(db.tree['revs'], {'dev-a': '1'});
    expect(db.writes, 1);
    expect(a.shadow.dirty, isEmpty);
  });

  test('a peer sees the write on its next poll', () async {
    final a = await engineFor('dev-a', db);
    final b = await engineFor('dev-b', db);
    final seen = <RemoteChange>[];
    b.remoteChanges.listen(seen.add);
    await a.write('read/h1/c1', {
      'read': true,
      'hlc': a.tick().toStr(),
      'url': '/c/1',
    });
    await b.poll();
    expect(seen.single.path, 'read/h1/c1');
    expect(b.shadow.node('read/h1/c1'), containsPair('read', true));
    expect(b.status.phase, SyncPhase.idle);
    expect(b.status.lastSync, isNotNull);
  });

  test('an unchanged revs node costs one read and no pull', () async {
    final a = await engineFor('dev-a', db);
    final b = await engineFor('dev-b', db);
    await a.write('library/h1', _title('One', a.tick()));
    await b.poll();
    final before = db.reads;
    await b.poll();
    expect(db.reads - before, 1);
  });

  test('own revs are ignored, so a lone device never pulls itself', () async {
    final a = await engineFor('dev-a', db);
    await a.write('library/h1', _title('One', a.tick()));
    final before = db.reads;
    await a.poll();
    expect(db.reads - before, 1);
  });

  test('a write lost to a concurrent PATCH is healed on sync', () async {
    final a = await engineFor('dev-a', db);
    await a.write('library/h1', _title('New', a.tick()));
    // Another device overwrote the whole node with an older copy.
    await db.patch({
      'library/h1': _title('Old', Hlc.fromStr('2000-01-01T00:00:00.000Z-0000-x')),
      'revs/dev-x': '7',
    });
    await a.poll();
    expect((db.tree['library']! as Map)['h1'], containsPair('title', 'New'));
  });

  test('nodes only the shadow holds are pushed by a forced sync', () async {
    final kv = MemoryKeyValueStore();
    final offline = await engineFor('dev-a', db, kv: kv, signedIn: false);
    await offline.write('progress/h1', {'chapterNumber': 3, 'page': 1});
    final a = await engineFor('dev-a', db, kv: kv);
    await a.syncNow();
    expect(db.tree['progress'], {
      'h1': {'chapterNumber': 3, 'page': 1},
    });
  });

  test('a failed push reports the error and retries later', () async {
    final a = await engineFor('dev-a', db);
    db.failWith = FirebaseSyncError('offline');
    await a.write('library/h1', _title('One', a.tick()));
    expect(a.status.phase, SyncPhase.error);
    expect(a.status.message, 'offline');
    expect(a.shadow.dirty, {'library/h1'});
    await a.poll();
    expect(a.status.phase, SyncPhase.error);
    db.failWith = null;
    await a.poll();
    expect(a.shadow.dirty, isEmpty);
    expect(a.status.phase, SyncPhase.idle);
  });

  test('a failing sign-in is an error, not a crash', () async {
    final a = SyncEngine(
      shadow: await SyncShadow.load(MemoryKeyValueStore()),
      deviceId: 'dev-a',
      open: () async => throw FirebaseSyncError('no session'),
    );
    final statuses = <SyncStatus>[];
    a.statusChanges.listen(statuses.add);
    await a.syncNow();
    await pumpEventQueue();
    expect(statuses.last.phase, SyncPhase.error);
    expect(a.status.phase, SyncPhase.error);
    a.reset();
    await a.dispose();
  });

  test('ticks stay ahead of every clock seen from peers', () async {
    final clock = TestClock();
    final a = await engineFor('dev-a', db, clock: TestClock()..advance(
      const Duration(days: 1),
    ));
    final b = await engineFor('dev-b', db, clock: clock);
    final future = a.tick();
    await a.write('library/h1', _title('One', future));
    await b.poll();
    expect(b.tick(), greaterThan(future));
  });

  test('the shadow survives a restart', () async {
    final kv = MemoryKeyValueStore();
    final a = await engineFor('dev-a', db, kv: kv);
    await a.write('library/h1', _title('One', a.tick()));
    final b = await engineFor('dev-b', db);
    await b.write('library/h2', _title('Two', b.tick()));
    await a.poll();
    final reloaded = await SyncShadow.load(kv);
    expect(reloaded.paths, containsAll(['library/h1', 'library/h2']));
    expect(reloaded.peers, {'dev-b': '1'});
    expect(reloaded.lastSync, isNotNull);
    expect(reloaded.lastHlc, isNotNull);
    expect(await reloaded.nextRev(), 2);
  });

  test('corrupt persisted entries are skipped', () async {
    final kv = MemoryKeyValueStore({
      'sync.node.library/x': '{bad',
      'sync.node.library/y': '[1]',
    });
    final shadow = await SyncShadow.load(kv);
    expect(shadow.paths, isEmpty);
  });

  test('flattenNodes walks to the namespace depth', () {
    expect(
      flattenNodes('read', {
        'h1': {
          'c1': {'read': true},
          'c2': 'junk',
        },
        'h2': 5,
      }, 2),
      {
        'read/h1/c1': {'read': true},
      },
    );
  });
}
