import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:kartka/sync/ui/sync_account_screen.dart';

import 'fake_account_controller.dart';

const _idle = SyncStatus(phase: SyncPhase.idle);
const _problem = {
  'suwayomi.password': "Couldn't decrypt synced Suwayomi password",
};

Future<FakeAccountController> _pump(
  WidgetTester t, {
  bool passphrase = false,
  Map<String, String> problems = const {},
}) async {
  final fake = FakeAccountController(
    _idle,
    passphrase: passphrase,
    problemsNow: problems,
  );
  await t.pumpWidget(MaterialApp(home: SyncAccountScreen(controller: fake)));
  await t.pumpAndSettle();
  return fake;
}

Finder _field(String label) => find.widgetWithText(TextField, label);

FilledButton _save(WidgetTester t) =>
    t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

void main() {
  testWidgets('no passphrase: Set asks twice, saves only a match', (t) async {
    final fake = await _pump(t);
    expect(find.text('Sync passphrase'), findsOneWidget);
    expect(find.textContaining('Not set'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Set'));
    await t.pumpAndSettle();
    expect(_save(t).onPressed, isNull, reason: 'empty');
    await t.enterText(_field('Passphrase'), 'correct horse');
    await t.enterText(_field('Repeat passphrase'), 'correct hors');
    await t.pump();
    expect(_save(t).onPressed, isNull, reason: 'mismatch');
    await t.enterText(_field('Repeat passphrase'), 'correct horse');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(fake.passphrases, ['correct horse']);
    expect(find.text('Set on this device'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Change'), findsOneWidget);
  });

  testWidgets('cancelling the dialog changes nothing', (t) async {
    final fake = await _pump(t, passphrase: true);
    await t.tap(find.widgetWithText(TextButton, 'Change'));
    await t.pumpAndSettle();
    expect(find.text('Change sync passphrase'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(fake.passphrases, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a secret it cannot open prompts once for a passphrase', (
    t,
  ) async {
    final fake = await _pump(t, problems: _problem);
    expect(find.text('Set sync passphrase'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text(_problem.values.single), findsOneWidget);
    fake.emitProblems({..._problem, 'suwayomi.username': 'x'});
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing, reason: 'only once');
    expect(find.text('x'), findsOneWidget);
    fake.emitProblems(const {});
    await t.pumpAndSettle();
    expect(find.text('x'), findsNothing);
  });

  testWidgets('with a passphrase set, problems show without a prompt', (
    t,
  ) async {
    await _pump(t, passphrase: true, problems: _problem);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(_problem.values.single), findsOneWidget);
  });
}
