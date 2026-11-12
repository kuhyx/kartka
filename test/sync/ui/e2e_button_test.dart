import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/e2e/e2e_unlock.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:kartka/sync/ui/sync_account_screen.dart';

import '../e2e/e2e_fixtures.dart';
import 'fake_account_controller.dart';

void main() {
  testWidgets('the e2e lock icon shows the state and saves a passphrase', (
    t,
  ) async {
    final secrets = MemoryKeyValueStore();
    final e2e = KartkaE2e(secrets, params: kTestArgon)..locked.value = true;
    final fake = FakeAccountController(
      const SyncStatus(phase: SyncPhase.error),
      e2e: e2e,
    );
    await t.pumpWidget(MaterialApp(home: SyncAccountScreen(controller: fake)));
    expect(find.byIcon(Icons.lock), findsWidgets);
    expect(find.byIcon(Icons.enhanced_encryption_outlined), findsOneWidget);
    await t.tap(
      find.descendant(
        of: find.byType(ListTile).last,
        matching: find.byType(IconButton),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'pw');
    await t.tap(find.byIcon(Icons.check));
    await t.pumpAndSettle();
    expect(await secrets.get('crdt_sync_e2e_passphrase'), 'pw');
    expect(fake.unlocks, 1);
    e2e.locked.value = false;
    await t.pump();
    expect(find.byIcon(Icons.lock_open), findsWidgets);
    expect(find.text('pw'), findsNothing);
  });

  testWidgets('no e2e key: no lock row', (t) async {
    final fake = FakeAccountController(const SyncStatus(phase: SyncPhase.idle));
    await t.pumpWidget(MaterialApp(home: SyncAccountScreen(controller: fake)));
    expect(find.byIcon(Icons.enhanced_encryption_outlined), findsNothing);
  });
}
