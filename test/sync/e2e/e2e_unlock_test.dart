import 'package:crdt_sync/crdt_sync.dart'
    show E2eLockReason, RemoteSyncError, resetE2eCopyMemo;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/e2e/e2e_unlock.dart';
import 'package:kartka/sync/e2e/sealed_transport.dart';
import 'package:kartka/sync/rtdb_transport.dart';

import 'e2e_fixtures.dart';

Matcher _locked(E2eLockReason reason) => throwsA(
  isA<E2eLockedSyncError>().having((e) => e.reason, 'reason', reason),
);

void main() {
  late InMemoryRtdb root;
  setUp(() {
    root = InMemoryRtdb();
    resetE2eCopyMemo();
  });

  test('no passphrase: locked, nothing written', () async {
    final e2e = testE2e(passphrase: null);
    await expectLater(e2e.unlock(root), _locked(E2eLockReason.needsPassphrase));
    expect(e2e.locked.value, isTrue);
    expect(root.writes, 0);
  });

  test('the first device makes the header, the next one opens it', () async {
    final a = testE2e();
    final ca = await a.unlock(root);
    expect(a.locked.value, isFalse);
    expect(root.tree['e2e'], isA<String>());
    final cb = await testE2e().unlock(root);
    final blob = await ca.seal('x', path: 'p');
    expect(await cb.open(blob, path: 'p'), 'x');
  });

  test('a wrong passphrase stays locked', () async {
    await testE2e().unlock(root);
    final wrong = testE2e(passphrase: 'other');
    await expectLater(wrong.unlock(root), _locked(E2eLockReason.wrongKey));
    expect(wrong.locked.value, isTrue);
  });

  test('a header nobody wrote is never overwritten', () async {
    root.tree['e2e'] = {'not': 'a header'};
    await expectLater(testE2e().unlock(root), _locked(E2eLockReason.badHeader));
    expect(root.tree['e2e'], {'not': 'a header'});
  });

  test('the derived key is cached in the secrets', () async {
    final secrets = MemoryKeyValueStore({'crdt_sync_e2e_passphrase': 'pw'});
    final e2e = KartkaE2e(secrets, params: kTestArgon);
    await e2e.unlock(root);
    final cached = await secrets.entries(prefix: 'crdt_sync_e2e_key:');
    expect(cached.keys, ['crdt_sync_e2e_key:kartka']);
    await secrets.remove('crdt_sync_e2e_passphrase');
    // Opens from the cache alone.
    await e2e.unlock(root);
    expect(e2e.locked.value, isFalse);
  });

  test('secure storage adapter maps onto the secrets', () async {
    final secrets = MemoryKeyValueStore();
    final s = SecretsSecureStorage(secrets);
    await s.write(key: 'a', value: '1');
    expect(await s.read(key: 'a'), '1');
    expect(await s.readAll(), {'a': '1'});
    await s.write(key: 'a', value: null);
    expect(await s.read(key: 'a'), isNull);
    await s.write(key: 'b', value: '2');
    await s.delete(key: 'b');
    expect(await secrets.entries(), isEmpty);
  });

  test('the header store stays inside the e2e root', () async {
    final h = E2eHeaderStore(root);
    expect(() => h.getFileText('kartka/e2e'), throwsA(isA<RemoteSyncError>()));
    expect(
      () => h.deleteFile(kE2eLayout.e2ePath),
      throwsA(isA<RemoteSyncError>()),
    );
    expect(await h.listDirectory(kE2eLayout.prefix), isEmpty);
    expect(await h.canAccessRemote(), isTrue);
    h.close();
  });
}
