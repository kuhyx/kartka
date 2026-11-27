import 'dart:async';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show WaitWatch;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/shown_wait_watch.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/paged_controller.dart';
import 'package:kartka/browse/ui/manga_grid.dart';
import 'package:kartka/core/models/models.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

PageResult<MangaSummary> _page(int page) => (
  items: [
    for (var i = 0; i < 2; i++)
      MangaSummary(sourceId: 's', url: '/$page/$i', title: 't$i'),
  ],
  hasNext: true,
);

void main() {
  testWidgets('the footer is timed only while a page is in flight, one '
      'wait per page (89e1ec6e)', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pending = <Completer<PageResult<MangaSummary>>>[];
    final c = PagedController<MangaSummary>((page) {
      if (page == 1) return Future.value(_page(1));
      final next = Completer<PageResult<MangaSummary>>();
      pending.add(next);
      return next.future;
    }, keyOf: (m) => m.url);
    addTearDown(c.dispose);
    await c.loadMore();
    await tester.pumpWidget(
      MaterialApp(
        home: BrowseScope(
          deps: Harness(withCovers: false).deps,
          child: Scaffold(body: PagedMangaGrid(c)),
        ),
      ),
    );
    // Idle between pages: more exist, none is being fetched.
    expect(c.loading, isFalse);
    expect(c.hasNext, isTrue);
    expect(find.byType(WaitWatch), findsNothing);

    unawaited(c.loadMore());
    await tester.pump();
    expect(find.byType(WaitWatch), findsOneWidget);
    final first = tester.widget<ShownWaitWatch>(find.byType(ShownWaitWatch));
    expect(first.key, const ValueKey(1));

    pending.single.complete(_page(2));
    await tester.pump();
    await tester.pump();
    // The short grid asks for page 3 at once: a new wait, not the old one.
    final second = tester.widget<ShownWaitWatch>(find.byType(ShownWaitWatch));
    expect(second.key, const ValueKey(2));
  });

  testWidgets('a page fetched below the screen is timed only once the '
      'footer shows (89e1ec6e)', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final next = Completer<PageResult<MangaSummary>>();
    final c = PagedController<MangaSummary>(
      (page) => page == 1
          ? Future.value((
              items: [
                for (var i = 0; i < 60; i++)
                  MangaSummary(sourceId: 's', url: '/$i', title: 't$i'),
              ],
              hasNext: true,
            ))
          : next.future,
      keyOf: (m) => m.url,
    );
    addTearDown(c.dispose);
    await c.loadMore();
    await tester.pumpWidget(
      MaterialApp(
        home: BrowseScope(
          deps: Harness(withCovers: false).deps,
          child: Scaffold(body: PagedMangaGrid(c)),
        ),
      ),
    );
    unawaited(c.loadMore());
    await tester.pump();
    expect(c.loading, isTrue);
    expect(find.byType(WaitWatch, skipOffstage: false), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -9000));
    await tester.pump();
    expect(find.byType(WaitWatch), findsOneWidget);
    next.complete((items: const <MangaSummary>[], hasNext: false));
    await tester.pump();
  });
}
