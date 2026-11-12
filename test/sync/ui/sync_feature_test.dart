import 'dart:async';

import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/library/repository_decorator.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sync/rtdb_reader.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/settings/sync_passphrase.dart';
import 'package:kartka/sync/settings/synced_settings.dart';
import 'package:kartka/sync/sync_feature.dart';
import 'package:kartka/sync/sync_runtime.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:kartka/sync/ui/sync_account_controller.dart';
import 'package:kartka/sync/ui/sync_account_screen.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

SyncRuntime _runtime(InMemoryRtdb db, {Future<String>? deviceId}) =>
    SyncRuntime(
      kv: MemoryKeyValueStore(),
      openTransport: () async => db,
      deviceId: () => deviceId ?? Future.value('dev-a'),
      startScheduler: false,
    );

Widget _app(KartkaFeature f) => MaterialApp.router(
  routerConfig: GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => Scaffold(
          body: Column(children: [for (final t in f.settingsTiles) t(c)]),
        ),
      ),
      ...f.routes,
    ],
  ),
);

void main() {
  test(
    'a synced setting starts the engine, signed out it stays local',
    () async {
      SharedPreferences.setMockInitialValues({});
      installFakeSecureStorage();
      final kv = MemoryKeyValueStore();
      final registry = KartkaRegistry.build(memoryPlatform(kv: kv), [
        syncFeature,
      ]);
      final settings = registry.maybe<SettingsSync>()! as SyncedSettings;
      await settings.changed('reader.settings', '{}', SettingsVault.plain);
      await settings.settled;
      expect((await kv.entries(prefix: 'sync.')).keys, contains('sync.dirty'));
    },
  );

  test('the controller keys secrets through the synced settings', () async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
    final runtime = _runtime(InMemoryRtdb());
    final engine = await runtime.engine;
    final bare = EngineAccountController(engine, runtime);
    expect(await bare.watchProblems().first, isEmpty);
    expect(await bare.hasPassphrase(), isFalse);
    await bare.setPassphrase('ignored');
    final secrets = MemoryKeyValueStore();
    final c = EngineAccountController(
      engine,
      runtime,
      SyncedSettings(
        started: runtime.started,
        start: () => runtime.engine,
        kv: MemoryKeyValueStore(),
        secrets: secrets,
        passphrase: SyncPassphrase(secrets, fallback: () async => null),
      ),
    );
    expect(await c.hasPassphrase(), isFalse);
    await c.setPassphrase('pp');
    expect(await c.hasPassphrase(), isTrue);
    expect(await secrets.get(kSyncPassphraseKey), 'pp');
    expect(await c.watchProblems().first, isEmpty);
    expect(c.e2e, isNull);
    await c.unlocked(); // resyncs through a freshly opened transport
    expect(engine.status.phase, SyncPhase.idle);
  });

  test('the feature registers its services without starting sync', () {
    final registry = KartkaRegistry.build(memoryPlatform(), [syncFeature]);
    expect(registry.maybe<RepositoryDecorator>(), isNotNull);
    expect(registry.maybe<BindingStoreDecorator>(), isNotNull);
    expect(registry.maybe<RtdbReader>(), isNotNull);
    expect(registry.maybe<SettingsSync>(), isA<SyncedSettings>());
    expect(registry.features.single.id, 'sync');
  });

  testWidgets('More → Sync opens the account screen, Sync now syncs', (
    t,
  ) async {
    final db = InMemoryRtdb();
    final f = syncFeatureWith(_runtime(db));
    await t.pumpWidget(_app(f));
    await t.tap(find.byIcon(Icons.cloud_sync_outlined));
    await t.pumpAndSettle();
    expect(find.byType(SyncAccountScreen), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.bySemanticsLabel('Sync now'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pump();
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(db.reads, greaterThan(0));
  });

  testWidgets('the route waits for the engine and shows start failures', (
    t,
  ) async {
    final pending = Completer<String>();
    final f = syncFeatureWith(
      _runtime(InMemoryRtdb(), deviceId: pending.future),
    );
    await t.pumpWidget(_app(f));
    await t.tap(find.byIcon(Icons.cloud_sync_outlined));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('no prefs'));
    await t.pump();
    await t.pump();
    expect(find.bySemanticsLabel('Sync could not start'), findsOneWidget);
    expect(find.textContaining('no prefs'), findsOneWidget);
    expect(find.textContaining('Sync could not start'), findsNothing);
  });

  testWidgets('Account opens sign-in and resyncs when it closes', (t) async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    final db = InMemoryRtdb();
    final f = syncFeatureWith(_runtime(db));
    await t.pumpWidget(_app(f));
    await t.tap(find.byIcon(Icons.cloud_sync_outlined));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.account_circle_outlined));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Sync settings'), findsOneWidget);
    final reads = db.reads;
    await t.runAsync(() async {
      await t.pageBack();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pumpAndSettle();
    expect(db.reads, greaterThan(reads), reason: 'resynced after the screen');
  });
}
