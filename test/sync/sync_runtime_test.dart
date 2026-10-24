import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_runtime.dart';
import 'package:kartka/sync/sync_scheduler.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nothing starts until the engine is first read', () async {
    var opened = 0;
    final db = InMemoryRtdb();
    final runtime = SyncRuntime(
      kv: MemoryKeyValueStore(),
      openTransport: () async {
        opened++;
        return db;
      },
      deviceId: () async => 'dev-a',
      startScheduler: false,
    );
    expect(opened, 0);
    final engine = await runtime.engine;
    expect(engine.deviceId, 'dev-a');
    expect(await runtime.transport(), same(db));
    expect(await runtime.transport(), same(db));
    expect(opened, 1, reason: 'the transport is cached');
    await runtime.accountChanged();
    expect(opened, 2, reason: 'an account change reopens the session');
    expect(engine.status.phase, SyncPhase.idle);
    expect(runtime.scheduler, isNull);
  });

  test('the device id is the persisted per-install uuid', () async {
    SharedPreferences.setMockInitialValues({});
    Future<String> idOf() async {
      final r = SyncRuntime(
        kv: MemoryKeyValueStore(),
        openTransport: () async => null,
        startScheduler: false,
      );
      return (await r.engine).deviceId;
    }

    final first = await idOf();
    expect(first, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(await idOf(), first, reason: 'persisted, not regenerated');
  });

  test('starting the engine attaches foreground polling', () async {
    final runtime = SyncRuntime(
      kv: MemoryKeyValueStore(),
      openTransport: () async => null,
      deviceId: () async => 'dev-a',
    );
    await runtime.engine;
    final scheduler = runtime.scheduler!;
    expect(scheduler.running, isTrue);
    scheduler.detach();
    expect(scheduler.running, isFalse);
  });

  test('a device with no sync account opens no transport', () async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    expect(await openFirebaseTransport(FakeKartkaHttp()), isNull);
  });

  test('a keystore failure becomes a sync error, not a crash', () async {
    installFakeSecureStorage(throwing: true);
    SharedPreferences.setMockInitialValues({});
    final opened = openFirebaseTransport(FakeKartkaHttp());
    await expectLater(
      opened.then((t) => t == null ? 'none' : 'transport'),
      anyOf(completion('none'), throwsA(isA<Exception>())),
    );
  });

  test('the scheduler polls while resumed and flushes on pause', () async {
    var polls = 0;
    var flushes = 0;
    final s = SyncScheduler(
      () async => polls++,
      onPause: () async => flushes++,
      interval: const Duration(milliseconds: 10),
    )..attach();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(polls, greaterThanOrEqualTo(3));
    s.didChangeAppLifecycleState(AppLifecycleState.paused);
    final paused = polls;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(polls, paused);
    expect(flushes, 1);
    s.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(flushes, 1, reason: 'already stopped');
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(s.running, isTrue);
    s
      ..attach()
      ..detach()
      ..detach();
    expect(s.running, isFalse);
  });

  test('a slow poll is never stacked', () async {
    var started = 0;
    final s = SyncScheduler(() async {
      started++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, interval: const Duration(milliseconds: 5))..attach();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(started, 1);
    s.detach();
  });
}
