import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/ui/global_search_screen.dart';

import '../fakes.dart';
import 'harness.dart';

void main() {
  testWidgets('one row per source; errors and empties stay local', (t) async {
    final ok = FakeSource('a', name: 'Good', perPage: 2);
    final bad = FakeSource('b', name: 'Broken')..failWith = StateError('down');
    final empty = FakeSource('c', name: 'Empty', perPage: 0);
    final h = Harness(sources: [ok, bad, empty]);
    await h.pump(t, const SizedBox(), at: globalSearchRoute('gate'));
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Title 1'), findsOneWidget);
    expect(find.textContaining('Failed:'), findsOneWidget);
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('slow sources show progress while others render', (t) async {
    final slow = FakeSource('s', name: 'Slow')..searchGate = Completer<void>();
    final h = Harness(sources: [slow]);
    await h.pump(t, const GlobalSearchScreen(query: 'x'), settle: false);
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    slow.searchGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Title 0'), findsOneWidget);
  });

  testWidgets('submitting a new query and opening a source', (t) async {
    final src = FakeSource('a', name: 'Good', pageCount: 1);
    final h = Harness(sources: [src]);
    await h.pump(t, const GlobalSearchScreen());
    expect(src.calls, isEmpty);
    await t.enterText(find.byKey(const ValueKey('global-search')), 'zz');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(src.calls, ['search(zz):1']);
    await t.tap(find.text('Good'));
    await t.pumpAndSettle();
    expect(find.text('Popular'), findsOneWidget);
    expect(src.calls.last, 'search(zz):1');
  });
}
