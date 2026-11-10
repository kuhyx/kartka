import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:kartka/sync/ui/google_route.dart';
import 'package:kartka/sync/ui/sync_account_controller.dart';
import 'package:kartka/sync/ui/sync_account_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_account_controller.dart';

Future<FakeAccountController> _pump(
  WidgetTester tester,
  SyncStatus status,
) async {
  final fake = FakeAccountController(status);
  await tester.pumpWidget(
    MaterialApp(home: SyncAccountScreen(controller: fake)),
  );
  return fake;
}

/// The spoken label of the [icon] glyph in the body (not the app bar).
String? _spoken(WidgetTester t, IconData icon) => t
    .widget<Icon>(
      find.descendant(of: find.byType(ListView), matching: find.byIcon(icon)),
    )
    .semanticLabel;

void main() {
  testWidgets('signed out: explains, offers sign-in, no sync', (t) async {
    final fake = await _pump(t, const SyncStatus(phase: SyncPhase.signedOut));
    expect(_spoken(t, Icons.cloud_off_outlined), 'Not signed in');
    expect(_spoken(t, Icons.history), 'Last sync: never');
    final syncNow = find.widgetWithIcon(FilledButton, Icons.sync);
    expect(t.widget<FilledButton>(syncNow).onPressed, isNull);
    await t.tap(find.bySemanticsLabel('Sign in'));
    expect(fake.manages, 1);
    expect(find.text('Not signed in'), findsNothing, reason: 'never painted');
  });

  testWidgets('signed in: status, last sync and Sync now work', (t) async {
    final at = DateTime(2026, 10, 24, 9, 5);
    final fake = await _pump(
      t,
      SyncStatus(phase: SyncPhase.idle, lastSync: at),
    );
    expect(_spoken(t, Icons.cloud_done_outlined), 'Signed in, up to date');
    expect(find.text('2026-10-24 09:05'), findsOneWidget);
    expect(_spoken(t, Icons.history), 'Last sync: 2026-10-24 09:05');
    await t.tap(find.bySemanticsLabel('Sync now'));
    expect(fake.syncs, 1);
    expect(fake.refreshes, 1, reason: 'opening the screen checks status');
    expect(find.bySemanticsLabel('Account (sign out)'), findsOneWidget);
  });

  testWidgets('live status: syncing disables the button, errors show', (
    t,
  ) async {
    final fake = await _pump(t, const SyncStatus(phase: SyncPhase.idle));
    fake.emit(const SyncStatus(phase: SyncPhase.syncing));
    await t.pump();
    expect(_spoken(t, Icons.cloud_sync_outlined), 'Syncing');
    final syncNow = find.widgetWithIcon(FilledButton, Icons.sync);
    expect(t.widget<FilledButton>(syncNow).onPressed, isNull);
    fake.emit(const SyncStatus(phase: SyncPhase.error, message: 'HTTP 401'));
    await t.pump();
    expect(_spoken(t, Icons.error_outline), 'Sync failed');
    expect(find.text('HTTP 401'), findsOneWidget, reason: 'server words stay');
    fake.emit(const SyncStatus(phase: SyncPhase.error));
    await t.pump();
    expect(find.text('HTTP 401'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  FilledButton googleButton(WidgetTester t) => t.widget<FilledButton>(
    find.ancestor(
      of: find.text('Sign in with Google'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ),
  );

  testWidgets('Google sign-in is offered when a route exists', (t) async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(
      MaterialApp(home: buildAccountSettingsScreen(route: GoogleRoute.plugin)),
    );
    await t.pumpAndSettle();
    expect(find.text('Sync settings'), findsOneWidget);
    expect(googleButton(t).onPressed, isNotNull);
    expect(find.textContaining('not available'), findsNothing);
  });

  testWidgets('tapping Google runs the route; a dismissed picker cancels', (
    t,
  ) async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    var asked = 0;
    await t.pumpWidget(
      MaterialApp(
        home: buildAccountSettingsScreen(
          route: GoogleRoute.plugin,
          sources: GoogleTokenSources(
            plugin: (_) async {
              asked++;
              return null;
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Sign in with Google'));
    await t.pumpAndSettle();
    expect(asked, 1);
    expect(find.text('Google sign-in was cancelled.'), findsOneWidget);
  });

  testWidgets('a platform with no route: no Google button, no sentence', (
    t,
  ) async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(
      MaterialApp(home: buildAccountSettingsScreen(route: GoogleRoute.none)),
    );
    await t.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsNothing);
    expect(find.textContaining('not available'), findsNothing);
  });

  testWidgets('connecting with a password reaches the sync opener', (t) async {
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(
      MaterialApp(home: buildAccountSettingsScreen(route: GoogleRoute.none)),
    );
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
