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
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pumpAndSettle();
  }

  testWidgets('log in, search, bind, then the button says Tracking', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.text('ANILIST'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Log in to ANILIST'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Yotsuba'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Yotsuba to!');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget, reason: 'chapter count, no word');
    expect(find.textContaining('chapters'), findsNothing);
    await tester.tap(find.text('Yotsuba to!').last);
    await tester.pumpAndSettle();
    expect((await store.all()).single.remoteId, '1');
    final unlisted = tester.widget<Icon>(find.byIcon(Icons.playlist_add));
    expect(unlisted.semanticLabel, 'Not on your list yet');
    Navigator.of(tester.element(find.byType(TrackerSection))).pop();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Tracking'), findsOneWidget);
  });

  testWidgets('search button and empty results', (tester) async {
    anilist
      ..loggedIn = true
      ..emptySearch = true;
    await openSheet(tester);
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pumpAndSettle();
    final none = tester.widget<Icon>(find.byIcon(Icons.search_off));
    expect(none.semanticLabel, 'No matches');
    expect(find.text('No matches'), findsNothing);
  });

  testWidgets('bound entry shows remote status and unbinds', (tester) async {
    anilist
      ..loggedIn = true
      ..remote['9'] = 5;
    await store.put(
      const TrackBinding(key: _k, service: 'anilist', remoteId: '9'),
    );
    await openSheet(tester, label: 'Tracking');
    expect(find.bySemanticsLabel('CURRENT · 5 chapters'), findsOneWidget);
    expect(find.text('CURRENT'), findsOneWidget, reason: "tracker's word");
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Unbind'));
    await tester.pumpAndSettle();
    expect(await store.all(), isEmpty);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('log out returns to the login button', (tester) async {
    anilist.loggedIn = true;
    await openSheet(tester);
    await tester.tap(find.bySemanticsLabel('Log out'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Log in to ANILIST'), findsOneWidget);
  });

  testWidgets('a failed login shows an error', (tester) async {
    anilist.loginError = Exception('denied');
    await openSheet(tester);
    await tester.tap(find.bySemanticsLabel('Log in to ANILIST'));
    await tester.pumpAndSettle();
    expect(find.textContaining('denied'), findsOneWidget);
  });

  testWidgets('a failed search and bind show errors', (tester) async {
    anilist
      ..loggedIn = true
      ..searchError = Exception('offline');
    await openSheet(tester);
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('a failed fetch shows the error in its own words', (
    tester,
  ) async {
    anilist
      ..loggedIn = true
      ..fetchError = Exception('HTTP 503');
    await store.put(
      const TrackBinding(key: _k, service: 'anilist', remoteId: '9'),
    );
    await openSheet(tester, label: 'Tracking');
    expect(find.textContaining('HTTP 503'), findsOneWidget);
  });

  testWidgets('a status row paints a score behind its glyph', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrackStatusRow(
            TrackStatus(
              remoteId: '1',
              chaptersRead: 3,
              totalChapters: 10,
              status: 'CURRENT',
              score: 8.5,
            ),
          ),
        ),
      ),
    );
    expect(find.text('3/10'), findsOneWidget);
    expect(find.text('8.5'), findsOneWidget);
    expect(find.byIcon(Icons.star_outline), findsOneWidget);
    expect(
      find.bySemanticsLabel('CURRENT · 3 / 10 chapters · score 8.5'),
      findsOneWidget,
    );
  });

  testWidgets('no trackers installed', (tester) async {
    service = TrackingService(
      trackers: () => const [],
      bindings: store,
      progress: () => LocalProgressRepository(MemoryKeyValueStore()),
    );
    await openSheet(tester);
    expect(find.bySemanticsLabel('No trackers installed'), findsOneWidget);
    expect(find.text('No trackers installed'), findsNothing);
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
