import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/library/state/library_deps.dart';

import '../../helpers/fake_updater.dart';
import '../support/fakes.dart';
import 'harness.dart';

Future<FakeUpdater> _pump(WidgetTester t, {bool seed = true}) async {
  final f = Fakes();
  if (seed) await f.deps.repos.library.upsert(entry('/a', title: 'Akira'));
  final updater = FakeUpdater();
  await pumpLibrary(
    t,
    LibraryDeps(repos: f.deps.repos, updater: updater, clock: () => t0),
  );
  return updater;
}

void main() {
  testWidgets('the app bar refresh runs update-all and shows the summary', (
    t,
  ) async {
    final u = await _pump(t);
    u.summary = const UpdateSummary(newChapters: 3, manga: 2, failed: 1);
    await t.tap(find.bySemanticsLabel('Update library'));
    await t.pumpAndSettle();
    expect(u.calls, 1);
    expect(
      find.bySemanticsLabel('3 new chapters in 2 manga · 1 failed'),
      findsOneWidget,
    );
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('pull-to-refresh on the grid runs update-all', (t) async {
    final u = await _pump(t);
    await t.fling(find.text('Akira'), const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    expect(u.calls, 1);
    expect(find.bySemanticsLabel('No new chapters'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
  });

  testWidgets('pull works on the empty state too', (t) async {
    final u = await _pump(t, seed: false);
    await t.fling(
      find.bySemanticsLabel('Your library is empty'),
      const Offset(0, 400),
      1000,
    );
    await t.pumpAndSettle();
    expect(u.calls, 1);
  });

  testWidgets('a run in flight shows its progress', (t) async {
    final u = await _pump(t);
    u.show(const UpdateProgress(3, 10));
    await t.pump();
    expect(find.text('3/10'), findsOneWidget);
    expect(find.bySemanticsLabel('Checking 3/10'), findsOneWidget);
    u.show(null);
    await t.pump();
    expect(find.text('3/10'), findsNothing);
  });

  testWidgets('no updater: no refresh action', (t) async {
    final f = Fakes();
    await pumpLibrary(t, f.deps);
    expect(find.bySemanticsLabel('Update library'), findsNothing);
    expect(find.byType(RefreshIndicator), findsNothing);
  });
}
