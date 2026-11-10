import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/tracking_service.dart';
import 'package:kartka/tracking/common/ui/tracker_section.dart';
import 'package:kartka/tracking/mangaupdates/mu_login_sheet.dart';
import 'package:kartka/tracking/mangaupdates/mu_models.dart';
import 'package:kartka/tracking/mangaupdates/mu_session.dart';
import 'package:kartka/tracking/mangaupdates/mu_settings_tile.dart';
import 'package:kartka/tracking/mangaupdates/mu_tracker.dart';

import 'mu_fakes.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The spoken login state of the settings tile's person glyph.
String? _who(WidgetTester t) => t
    .widget<Icon>(
      find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.icon == Icons.person || w.icon == Icons.person_off_outlined),
      ),
    )
    .semanticLabel;

Future<void> _type(WidgetTester t, String user, String pass) async {
  await t.enterText(find.byKey(const Key('mu-username')), user);
  await t.enterText(find.byKey(const Key('mu-password')), pass);
}

void main() {
  group('MuLoginForm', () {
    testWidgets('empty fields: asks for both, no login', (t) async {
      var calls = 0;
      await t.pumpWidget(
        _app(MuLoginForm(login: (_, _) async => calls++, onDone: () {})),
      );
      await t.tap(find.bySemanticsLabel('Log in'));
      await t.pump();
      expect(
        find.bySemanticsLabel('Enter your username and password.'),
        findsOneWidget,
      );
      expect(find.text('Enter your username and password.'), findsNothing);
      expect(calls, 0);
      // Filling both in clears the mark once the login goes through.
      await _type(t, 'a', 'b');
      await t.tap(find.bySemanticsLabel('Log in'));
      await t.pump();
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(calls, 1);
    });

    testWidgets('Enter in password submits trimmed username', (t) async {
      String? got;
      var done = false;
      await t.pumpWidget(
        _app(
          MuLoginForm(
            login: (u, p) async => got = '$u:$p',
            onDone: () => done = true,
          ),
        ),
      );
      await _type(t, ' kuhy ', 'pw');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(got, 'kuhy:pw');
      expect(done, isTrue);
    });

    testWidgets('server refusal is shown inline', (t) async {
      await t.pumpWidget(
        _app(
          MuLoginForm(
            login: (_, _) async =>
                throw const MuAuthException('Invalid username or password'),
            onDone: () => fail('must not finish'),
          ),
        ),
      );
      await _type(t, 'a', 'b');
      await t.tap(find.bySemanticsLabel('Log in'));
      await t.pump();
      expect(find.text('Invalid username or password'), findsOneWidget);
      expect(find.bySemanticsLabel('Log in'), findsOneWidget);
    });
  });

  group('MuSettingsTile', () {
    late KartkaResponse Function(FakeRequest r) handler;
    late MangaUpdatesTracker tracker;
    late MuSessionStore store;

    // Built inside each testWidgets body: the limiter's futures must belong
    // to the test's fake-async zone, or they never complete under pump.
    void build() {
      final s = buildStack(FakeKartkaHttp((r) => handler(r)), FakeClock());
      store = s.store;
      tracker = MangaUpdatesTracker(api: s.api, store: store);
    }

    setUp(() => handler = (_) => fx('login_ok.json'));

    testWidgets('logs in through the sheet', (t) async {
      build();
      await t.pumpWidget(_app(MuSettingsTile(tracker: tracker)));
      await t.pumpAndSettle();
      expect(_who(t), 'Not logged in');
      await t.tap(find.text('MangaUpdates'));
      await t.pumpAndSettle();
      await _type(t, 'kuhy', 'pw');
      await t.tap(find.bySemanticsLabel('Log in'));
      await t.pumpAndSettle();
      expect(find.byType(MuLoginForm), findsNothing);
      expect(_who(t), 'Logged in');
      expect(find.text('kuhy'), findsOneWidget);
    });

    testWidgets('Escape closes the sheet without logging in', (t) async {
      build();
      await t.pumpWidget(_app(MuSettingsTile(tracker: tracker)));
      await t.pumpAndSettle();
      await t.tap(find.text('MangaUpdates'));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(MuLoginForm), findsNothing);
      expect(_who(t), 'Not logged in');
    });

    testWidgets('logs out after confirming; cancel keeps it', (t) async {
      build();
      await store.write(testSession);
      handler = (_) => fx('logout_ok.json');
      await t.pumpWidget(_app(MuSettingsTile(tracker: tracker)));
      await t.pumpAndSettle();
      expect(find.text('kuhy'), findsOneWidget);
      await t.tap(find.text('MangaUpdates'));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Log out of MangaUpdates?'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('kuhy'), findsOneWidget);
      await t.tap(find.text('MangaUpdates'));
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Log out'));
      await t.pumpAndSettle();
      expect(_who(t), 'Not logged in');
      expect(await store.read(), isNull);
    });
  });

  // The track sheet opens the credentials sheet for a CredentialsLogin
  // tracker; the plain login() branch is covered by track_sheet_test.dart.
  testWidgets('TrackerSection logs MangaUpdates in through the sheet', (
    t,
  ) async {
    final s = buildStack(
      FakeKartkaHttp((_) => fx('login_ok.json')),
      FakeClock(),
    );
    final tracker = MangaUpdatesTracker(api: s.api, store: s.store);
    final service = TrackingService(
      trackers: () => [tracker],
      bindings: KvBindingStore(MemoryKeyValueStore()),
      progress: () => LocalProgressRepository(MemoryKeyValueStore()),
    );
    await t.pumpWidget(
      _app(
        TrackerSection(
          service: service,
          tracker: tracker,
          mangaKey: 'mangadex|/manga/abc',
          title: 'Yotsuba',
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Log in to MangaUpdates').first);
    await t.pumpAndSettle();
    expect(find.byType(MuLoginForm), findsOneWidget);
    await _type(t, 'kuhy', 'pw');
    await t.tap(find.bySemanticsLabel('Log in'));
    await t.pumpAndSettle();
    expect(find.byType(MuLoginForm), findsNothing);
    expect(find.bySemanticsLabel('Log out'), findsOneWidget);
  });

  testWidgets('showMuLoginSheet returns false when dismissed', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      _app(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final result = showMuLoginSheet(ctx, (_, _) async {});
    await t.pumpAndSettle();
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(await result, isFalse);
  });
}
