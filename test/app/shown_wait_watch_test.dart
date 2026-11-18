import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show WaitWatch;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/shown_wait_watch.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final watches = find.byType(WaitWatch, skipOffstage: false);
  final bars = find.byType(LinearProgressIndicator, skipOffstage: false);

  Future<NavigatorState> pump(WidgetTester tester, Widget loader) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: Scaffold(body: loader),
      ),
    );
    return nav.currentState!;
  }

  testWidgets('a loader on screen is timed', (tester) async {
    await pump(
      tester,
      const ShownWaitWatch(
        operation: 'details.refresh',
        child: LinearProgressIndicator(),
      ),
    );
    expect(watches, findsOneWidget);
    expect(tester.widget<WaitWatch>(watches).operation, 'details.refresh');
  });

  testWidgets('a page covered by a pushed route stops timing, and '
      'starts again when it is shown', (tester) async {
    final nav = await pump(
      tester,
      const ShownWaitWatch(
        operation: 'details.refresh',
        child: LinearProgressIndicator(),
      ),
    );
    final route = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('reader')),
    );
    nav.push(route);
    await tester.pumpAndSettle();
    expect(watches, findsNothing);
    // The loader itself stays, so the page looks the same when uncovered.
    expect(bars, findsOneWidget);
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(watches, findsOneWidget);
  });

  testWidgets('centered shows a spinner under the watch', (tester) async {
    await pump(tester, const ShownWaitWatch.centered('library.load'));
    expect(watches, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
