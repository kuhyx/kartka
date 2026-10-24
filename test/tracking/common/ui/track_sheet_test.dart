import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/track_binding.dart';
import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/common/tracking_service.dart';
import 'package:kartka/tracking/common/ui/track_button.dart';
import 'package:kartka/tracking/common/ui/tracker_section.dart';

import '../service_fakes.dart';

const _k = 'mangadex|/manga/abc';

void main() {
  late FakeTracker anilist;
  late KvBindingStore store;
  late TrackingService service;

  setUp(() {
    anilist = FakeTracker(loggedIn: false);
    store = KvBindingStore(MemoryKeyValueStore());
    service = TrackingService(
      trackers: () => [anilist],
      bindings: store,
      progress: () => LocalProgressRepository(MemoryKeyValueStore()),
    );
  });

  Future<void> pumpButton(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: TrackButton(service: service, mangaKey: _k, title: 'Yotsuba'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester, {String label = 'Track'}) async {
    await pumpButton(tester);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('log in, search, bind, then the button says Tracking', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.text('ANILIST'), findsOneWidget);
    await tester.tap(find.text('Log in to ANILIST'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Yotsuba'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Yotsuba to!');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yotsuba to!').last);
    await tester.pumpAndSettle();
    expect((await store.all()).single.remoteId, '1');
    expect(find.text('Not on your list yet'), findsOneWidget);
    Navigator.of(tester.element(find.byType(TrackerSection))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Tracking'), findsOneWidget);
  });

  testWidgets('search button and empty results', (tester) async {
    anilist
      ..loggedIn = true
      ..emptySearch = true;
    await openSheet(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('bound entry shows remote status and unbinds', (tester) async {
    anilist
      ..loggedIn = true
      ..remote['9'] = 5;
    await store.put(
      const TrackBinding(key: _k, service: 'anilist', remoteId: '9'),
    );
    await openSheet(tester, label: 'Tracking');
    expect(find.text('CURRENT · 5 chapters'), findsOneWidget);
    await tester.tap(find.text('Unbind'));
    await tester.pumpAndSettle();
    expect(await store.all(), isEmpty);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('log out returns to the login button', (tester) async {
    anilist.loggedIn = true;
    await openSheet(tester);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Log in to ANILIST'), findsOneWidget);
  });

  testWidgets('a failed login shows an error', (tester) async {
    anilist.loginError = Exception('denied');
    await openSheet(tester);
    await tester.tap(find.text('Log in to ANILIST'));
    await tester.pumpAndSettle();
    expect(find.textContaining('denied'), findsOneWidget);
  });

  testWidgets('a failed search and bind show errors', (tester) async {
    anilist
      ..loggedIn = true
      ..searchError = Exception('offline');
    await openSheet(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('no trackers installed', (tester) async {
    service = TrackingService(
      trackers: () => const [],
      bindings: store,
      progress: () => LocalProgressRepository(MemoryKeyValueStore()),
    );
    await openSheet(tester);
    expect(find.text('No trackers installed'), findsOneWidget);
  });

  test('formatStatus', () {
    expect(formatStatus(null), 'Not on your list yet');
    expect(
      formatStatus(
        const TrackStatus(
          remoteId: '1',
          chaptersRead: 3,
          totalChapters: 10,
          status: 'CURRENT',
          score: 8.5,
        ),
      ),
      'CURRENT · 3 / 10 chapters · score 8.5',
    );
  });
}
