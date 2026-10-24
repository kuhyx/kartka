import 'dart:async';

import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/library/repository_decorator.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sync/rtdb_reader.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_feature.dart';
import 'package:kartka/sync/sync_runtime.dart';
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
  test('the feature registers its services without starting sync', () {
    final registry = KartkaRegistry.build(memoryPlatform(), [syncFeature]);
    expect(registry.maybe<RepositoryDecorator>(), isNotNull);
    expect(registry.maybe<BindingStoreDecorator>(), isNotNull);
    expect(registry.maybe<RtdbReader>(), isNotNull);
    expect(registry.features.single.id, 'sync');
  });

  testWidgets('More → Sync opens the account screen, Sync now syncs', (
    t,
  ) async {
    final db = InMemoryRtdb();
    final f = syncFeatureWith(_runtime(db));
    await t.pumpWidget(_app(f));
    await t.tap(find.text('Sync'));
    await t.pumpAndSettle();
    expect(find.byType(SyncAccountScreen), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.text('Sync now'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pump();
    expect(find.text('Signed in, up to date'), findsOneWidget);
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
    await t.tap(find.text('Sync'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('no prefs'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('Sync could not start'), findsOneWidget);
  });

  testWidgets('Account opens sign-in and resyncs when it closes', (t) async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    final db = InMemoryRtdb();
    final f = syncFeatureWith(_runtime(db));
    await t.pumpWidget(_app(f));
    await t.tap(find.text('Sync'));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.account_circle_outlined));
    await t.pumpAndSettle();
    expect(find.text('Sync settings'), findsOneWidget);
    final reads = db.reads;
    await t.runAsync(() async {
      await t.pageBack();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pumpAndSettle();
    expect(db.reads, greaterThan(reads), reason: 'resynced after the screen');
  });
}
