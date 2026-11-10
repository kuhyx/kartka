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

Finder _field(String spoken) => find.byKey(Key('passphrase-$spoken'));

IconButton _save(WidgetTester t) =>
    t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check));

/// The spoken labels of the red lock glyphs, one per sync problem.
List<String?> _problems(WidgetTester t) => t
    .widgetList<Icon>(find.byIcon(Icons.lock_outline))
    .map((i) => i.semanticLabel)
    .toList();

void main() {
  testWidgets('no passphrase: Set asks twice, saves only a match', (t) async {
    final fake = await _pump(t);
    final key = t.widget<Icon>(find.byIcon(Icons.key_outlined));
    expect(key.semanticLabel, 'Sync passphrase');
    expect(find.byIcon(Icons.lock_open), findsOneWidget, reason: 'not set');
    await t.tap(find.bySemanticsLabel('Set passphrase'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Set sync passphrase'), findsOneWidget);
    expect(_save(t).onPressed, isNull, reason: 'empty');
    await t.enterText(_field('Passphrase'), 'correct horse');
    await t.enterText(_field('Repeat passphrase'), 'correct hors');
    await t.pump();
    expect(_save(t).onPressed, isNull, reason: 'mismatch');
    await t.enterText(_field('Repeat passphrase'), 'correct horse');
    await t.pump();
    await t.tap(find.bySemanticsLabel('Save'));
    await t.pumpAndSettle();
    expect(fake.passphrases, ['correct horse']);
    expect(find.byIcon(Icons.lock_open), findsNothing);
    expect(find.byIcon(Icons.lock), findsOneWidget, reason: 'set');
    expect(find.bySemanticsLabel('Change'), findsOneWidget);
  });

  testWidgets('cancelling the dialog changes nothing', (t) async {
    final fake = await _pump(t, passphrase: true);
    await t.tap(find.bySemanticsLabel('Change'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Change sync passphrase'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Cancel'));
    await t.pumpAndSettle();
    expect(fake.passphrases, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a secret it cannot open prompts once for a passphrase', (
    t,
  ) async {
    final fake = await _pump(t, problems: _problem);
    expect(find.bySemanticsLabel('Set sync passphrase'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Cancel'));
    await t.pumpAndSettle();
    expect(_problems(t), [_problem.values.single]);
    expect(find.text(_problem.values.single), findsNothing);
    fake.emitProblems({..._problem, 'suwayomi.username': 'x'});
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing, reason: 'only once');
    expect(_problems(t), [_problem.values.single, 'x']);
    fake.emitProblems(const {});
    await t.pumpAndSettle();
    expect(_problems(t), isEmpty);
  });

  testWidgets('with a passphrase set, problems show without a prompt', (
    t,
  ) async {
    await _pump(t, passphrase: true, problems: _problem);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_problems(t), [_problem.values.single]);
  });
}
