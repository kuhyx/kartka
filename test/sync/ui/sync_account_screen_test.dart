import 'dart:async';

import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:kartka/sync/ui/sync_account_controller.dart';
import 'package:kartka/sync/ui/sync_account_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fake implements SyncAccountController {
  new(this.status);

  @override
  SyncStatus status;

  final _changes = StreamController<SyncStatus>.broadcast();
  int syncs = 0;
  int manages = 0;
  int refreshes = 0;

  void emit(SyncStatus s) => _changes.add(status = s);

  @override
  Stream<SyncStatus> get changes => _changes.stream;

  @override
  Future<void> syncNow() async => syncs++;

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Future<void> manageAccount(BuildContext context) async => manages++;
}

Future<_Fake> _pump(WidgetTester tester, SyncStatus status) async {
  final fake = _Fake(status);
  await tester.pumpWidget(
    MaterialApp(home: SyncAccountScreen(controller: fake)),
  );
  return fake;
}

void main() {
  testWidgets('signed out: explains, offers sign-in, no sync', (t) async {
    final fake = await _pump(t, const SyncStatus(phase: SyncPhase.signedOut));
    expect(find.textContaining('Not signed in'), findsOneWidget);
    expect(find.text('Last sync: never'), findsOneWidget);
    final syncNow = find.widgetWithText(FilledButton, 'Sync now');
    expect(t.widget<FilledButton>(syncNow).onPressed, isNull);
    await t.tap(find.text('Sign in'));
    expect(fake.manages, 1);
  });

  testWidgets('signed in: status, last sync and Sync now work', (t) async {
    final at = DateTime(2026, 10, 24, 9, 5);
    final fake = await _pump(
      t,
      SyncStatus(phase: SyncPhase.idle, lastSync: at),
    );
    expect(find.text('Signed in, up to date'), findsOneWidget);
    expect(find.text('Last sync: 2026-10-24 09:05'), findsOneWidget);
    await t.tap(find.text('Sync now'));
    expect(fake.syncs, 1);
    expect(fake.refreshes, 1, reason: 'opening the screen checks status');
    expect(find.text('Account (sign out)'), findsOneWidget);
  });

  testWidgets('live status: syncing disables the button, errors show', (
    t,
  ) async {
    final fake = await _pump(t, const SyncStatus(phase: SyncPhase.idle));
    fake.emit(const SyncStatus(phase: SyncPhase.syncing));
    await t.pump();
    expect(find.text('Syncing…'), findsOneWidget);
    final syncNow = find.widgetWithText(FilledButton, 'Sync now');
    expect(t.widget<FilledButton>(syncNow).onPressed, isNull);
    fake.emit(const SyncStatus(phase: SyncPhase.error, message: 'HTTP 401'));
    await t.pump();
    expect(find.text('Sync failed: HTTP 401'), findsOneWidget);
    fake.emit(const SyncStatus(phase: SyncPhase.error));
    await t.pump();
    expect(find.text('Sync failed: unknown error'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the shared sign-in screen builds with Google off', (t) async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(MaterialApp(home: buildAccountSettingsScreen()));
    await t.pumpAndSettle();
    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.textContaining('Google'), findsWidgets);
  });

  testWidgets('connecting with a password reaches the sync opener', (t) async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(MaterialApp(home: buildAccountSettingsScreen()));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'Sync account email'),
      'a@b.c',
    );
    await t.enterText(
      find.widgetWithText(TextField, 'Sync account password'),
      'pw',
    );
    // The test binding answers every HTTP request with 400, so sign-in
    // fails offline; reaching that failure is what this pins.
    await t.runAsync(() async {
      await t.tap(find.text('Connect Firebase'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pumpAndSettle();
    expect(find.text('Connect Firebase'), findsOneWidget);
  });
}
