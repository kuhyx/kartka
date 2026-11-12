import 'package:crdt_sync/crdt_sync.dart' show FirebaseSyncError;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/e2e/sealed_transport.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_shadow.dart';
import 'package:kartka/sync/sync_status.dart';

import 'e2e_fixtures.dart';

void main() {
  late InMemoryRtdb old;
  late InMemoryRtdb fresh;
  late SealedTransport sealed;

  Future<SyncEngine> engine(String id, [KeyValueStore? kv]) async => SyncEngine(
    shadow: await SyncShadow.load(kv ?? MemoryKeyValueStore()),
    deviceId: id,
    open: () async => sealed,
  );

  setUp(() async {
    old = InMemoryRtdb({
      'revs': {'dev-old': '4'},
      'library': {
        'h1': {
          'title': 'Berserk',
          kHlcField: {'title': '2026-01-01T00:00:00.000Z-0000-dev-old'},
        },
      },
      'read': {
        'h1': {
          'c1': {'read': true, kHlcField: '2026-01-01T00:00:00.000Z-0000-x'},
        },
      },
    });
    fresh = InMemoryRtdb();
    sealed = SealedTransport(
      fresh,
      await testCipher(),
      legacy: LegacyTree(old),
    );
  });

  test('the old tree is copied, sealed, and never written', () async {
    final before = canon(old.tree);
    final a = await engine('dev-a');
    await a.poll();
    expect(a.shadow.node('library/h1'), containsPair('title', 'Berserk'));
    expect(await sealed.get('library/h1'), containsPair('title', 'Berserk'));
    expect(await sealed.get('read/h1/c1'), containsPair('read', true));
    expect(canon(fresh.tree), isNot(contains('Berserk')));
    expect(canon(old.tree), before);
    expect(old.writes, 0);
    // A second device finds it in the e2e root, sealed.
    final b = await engine('dev-b');
    await b.poll();
    expect(b.shadow.node('library/h1'), containsPair('title', 'Berserk'));
  });

  test('copies again only when the old revisions change', () async {
    final kv = MemoryKeyValueStore();
    final a = await engine('dev-a', kv);
    await a.poll();
    final reads = old.reads;
    await a.poll();
    expect(old.reads - reads, 1, reason: 'revs only');
    // An old build writes there; restart picks it up.
    old.tree['revs'] = {'dev-old': '5'};
    (old.tree['library']! as Map<String, Object?>)['h2'] = {
      'title': 'Vagabond',
      kHlcField: {'title': '2026-01-02T00:00:00.000Z-0000-dev-old'},
    };
    final again = await engine('dev-a', kv);
    await again.poll();
    expect(await sealed.get('library/h2'), containsPair('title', 'Vagabond'));
  });

  test('a failed sync copies again next time', () async {
    final kv = MemoryKeyValueStore();
    fresh.failWith = FirebaseSyncError('offline');
    final a = await engine('dev-a', kv);
    await a.poll();
    expect(a.status.phase, SyncPhase.error);
    fresh.failWith = null;
    final b = await engine('dev-a', kv);
    await b.poll();
    expect(await sealed.get('library/h1'), containsPair('title', 'Berserk'));
  });

  test('without a legacy tree nothing is copied', () async {
    sealed = SealedTransport(fresh, await testCipher());
    final a = await engine('dev-a');
    await a.poll();
    expect(fresh.tree, isEmpty);
  });
}
