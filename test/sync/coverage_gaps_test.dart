import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sync/rtdb_reader.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_feature.dart';
import 'package:kartka/sync/sync_runtime.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_harness.dart';
import 'fakes.dart';

/// A signed-in crdt_sync client whose HTTP is [handler], with a live token.
FirebaseRestClient _client(MockClientHandler handler) {
  final saved = <String, String>{
    SecureCredentialStore.defaultKey: jsonEncode({
      'id_token': 'tok',
      'refresh_token': 'r',
      'expires_at': '2099-01-01T00:00:00.000Z',
    }),
  };
  final mock = MockClient(handler);
  return FirebaseRestClient(
    databaseUrl: 'https://db.example',
    auth: FirebaseTokenProvider(
      apiKey: 'k',
      store: SecureCredentialStore(
        read: (k) async => saved[k],
        write: (k, v) async => saved[k] = v,
        delete: (k) async => saved.remove(k),
      ),
      httpClient: mock,
    ),
    httpClient: mock,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a signed-in client becomes a working transport', () async {
    final patches = <http.Request>[];
    final client = _client((r) async {
      patches.add(r);
      return http.Response('{}', 200);
    });
    final reads = FakeKartkaHttp((_) => FakeKartkaHttp.text('"7"'));
    final t = (await openFirebaseTransport(reads, open: () async => client))!;
    expect(await t.get('revs/dev-a'), '7');
    expect(reads.requests.single.url.queryParameters['auth'], 'tok');
    await t.patch({'revs/dev-a': '8'});
    expect(patches.single.method, 'PATCH');
    expect(patches.single.url.path, '/kartka.json');
    expect(jsonDecode(patches.single.body), {'revs/dev-a': '8'});
  });

  test('non-sync failures while opening become sync errors', () async {
    expect(
      openFirebaseTransport(
        FakeKartkaHttp(),
        open: () async => throw PlatformException(code: 'keystore'),
      ),
      throwsA(isA<FirebaseSyncError>()),
    );
    expect(
      openFirebaseTransport(
        FakeKartkaHttp(),
        open: () async => throw FirebaseAuthError('bad'),
      ),
      throwsA(isA<FirebaseAuthError>()),
    );
  });

  test('the registered reader opens the real session lazily', () async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    final registry = KartkaRegistry.build(memoryPlatform(), [syncFeature]);
    expect(await registry.maybe<RtdbReader>()!.get('source_health'), isNull);
  });

  test('a successful push after a failure reports idle again', () async {
    final db = InMemoryRtdb();
    final a = await engineFor('dev-a', db);
    db.failWith = FirebaseSyncError('offline');
    await a.write('library/h', {'title': 'x'});
    expect(a.status.phase, SyncPhase.error);
    db.failWith = null;
    await a.write('library/h2', {'title': 'y'});
    expect(a.status.phase, SyncPhase.idle);
  });

  test('SyncStatus is a value', () {
    final at = DateTime.utc(2026);
    final a = SyncStatus(phase: SyncPhase.idle, lastSync: at);
    final b = SyncStatus(phase: SyncPhase.idle, lastSync: at);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == const SyncStatus(phase: SyncPhase.error), isFalse);
    expect(a.copyWith(phase: SyncPhase.syncing).lastSync, at);
    expect('$a', contains('idle'));
  });

  test('SyncRuntime without a transport stays signed out', () async {
    final runtime = SyncRuntime(
      kv: memoryPlatform().kv,
      openTransport: () async => null,
      deviceId: () async => 'dev-a',
      startScheduler: false,
    );
    final engine = await runtime.engine;
    await engine.poll();
    expect(engine.status.phase, SyncPhase.signedOut);
    expect(await runtime.transport(), isNull);
  });

  test('removing an entry sync never saw still removes it locally', () async {
    final d = await Device.create('dev-a', InMemoryRtdb());
    await d.library.remove('mangadex|/manga/404');
    expect(await d.library.watch().first, isEmpty);
    await d.dispose();
  });
}
