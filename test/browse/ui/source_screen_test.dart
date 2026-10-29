import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/ui/source_screen.dart';

import '../fakes.dart';
import 'harness.dart';

void main() {
  testWidgets('popular loads pages until the viewport is full', (t) async {
    final src = FakeSource('mangadex', pageCount: 3, perPage: 2);
    final h = Harness(sources: [src]);
    await h.pump(t, const SizedBox(), at: sourceRoute('mangadex'));
    expect(src.calls, ['popular:1', 'popular:2', 'popular:3']);
    expect(find.text('Title 5'), findsOneWidget);
  });

  testWidgets('scrolling near the end loads the next page', (t) async {
    final src = FakeSource('mangadex', pageCount: 3, perPage: 30);
    final h = Harness(sources: [src]);
    await h.pump(
      t,
      const SizedBox(),
      at: sourceRoute('mangadex'),
      settle: false,
    );
    await t.pump();
    expect(src.calls, ['popular:1']);
    await t.drag(find.byType(CustomScrollView), const Offset(0, -2400));
    await t.pump();
    await t.pump();
    expect(src.calls, contains('popular:2'));
  });

  testWidgets('latest tab and search tab', (t) async {
    final src = FakeSource('mangadex', pageCount: 1);
    final h = Harness(sources: [src]);
    await h.pump(t, const SizedBox(), at: sourceRoute('mangadex'));
    await t.tap(find.text('Latest'));
    await t.pumpAndSettle();
    expect(src.calls, contains('latest:1'));
    await t.tap(find.text('Search'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('source-search')), ' ');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(src.calls.where((c) => c.startsWith('search')), isEmpty);
    await t.enterText(find.byKey(const ValueKey('source-search')), 'gate');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(src.calls, contains('search(gate):1'));
  });

  testWidgets('opened with a query starts on its results', (t) async {
    final src = FakeSource('mangadex', pageCount: 1);
    final h = Harness(sources: [src]);
    await h.pump(
      t,
      const SizedBox(),
      at: sourceRoute('mangadex', query: 'gate'),
    );
    expect(src.calls, contains('search(gate):1'));
  });

  testWidgets('a failing page offers Retry', (t) async {
    final src = FakeSource('mangadex', pageCount: 1)
      ..failWith = StateError('x');
    final h = Harness(sources: [src]);
    await h.pump(t, const SizedBox(), at: sourceRoute('mangadex'));
    expect(find.textContaining('Could not load'), findsOneWidget);
    final logged = (await t.runAsync(h.diagnostics.entries))!.single;
    expect(logged.kind, 'browse.page');
    expect(logged.sourceId, 'mangadex');
    expect(logged.error, 'Bad state: x');
    src.failWith = null;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Title 0'), findsOneWidget);
  });

  testWidgets('an empty source shows the empty state', (t) async {
    final src = FakeSource('mangadex', pageCount: 1, perPage: 0);
    final h = Harness(sources: [src]);
    await h.pump(t, const SizedBox(), at: sourceRoute('mangadex'));
    expect(find.text('Nothing here'), findsOneWidget);
  });

  testWidgets('unknown source shows unavailable', (t) async {
    final h = Harness();
    await h.pump(t, const SourceScreen('plugin:gone'));
    expect(find.text('Source unavailable'), findsOneWidget);
  });

  testWidgets('tapping a tile opens the detail route', (t) async {
    final src = FakeSource('mangadex', pageCount: 1, perPage: 1);
    final h = Harness(sources: [src]);
    await h.pump(t, const SizedBox(), at: sourceRoute('mangadex'));
    await t.tap(find.text('Title 0'));
    await t.pumpAndSettle();
    expect(find.text('Detail title'), findsOneWidget);
    expect(src.calls, contains('details:/m/0?x=1#f'));
  });
}
