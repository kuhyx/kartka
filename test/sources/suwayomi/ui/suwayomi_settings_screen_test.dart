import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';
import 'package:kartka/sources/suwayomi/ui/suwayomi_settings_screen.dart';

import '../fakes.dart';

void main() {
  late SuwayomiSettingsStore store;
  late List<SuwayomiSettings> tested;
  var opened = 0;

  setUp(() {
    store = SuwayomiSettingsStore(
      kv: MemoryKeyValueStore(),
      secrets: MemoryKeyValueStore(),
    );
    tested = [];
    opened = 0;
  });

  Future<void> pump(
    WidgetTester tester, {
    Future<String> Function(SuwayomiSettings)? test,
    Stream<List<String>>? problems,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: SuwayomiSettingsScreen(
          store: store,
          testConnection:
              test ??
              (s) async {
                tested.add(s);
                return 'Suwayomi-Server v2.4.2366';
              },
          onOpenExtensions: () => opened++,
          syncProblems: problems,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('loads stored settings into the fields', (tester) async {
    await store.save(fixtureSettings);
    await pump(tester);
    expect(find.text('http://127.0.0.1:4599/'), findsOneWidget);
    expect(find.text('kartka'), findsOneWidget);
    final password = tester.widget<TextField>(field('Password'));
    expect(password.obscureText, isTrue);
  });

  testWidgets('saves what was typed, Enter submits', (tester) async {
    await pump(tester);
    await tester.enterText(field('Server URL'), 'https://m.example.org');
    await tester.enterText(field('Username'), 'u');
    await tester.enterText(field('Password'), 'p');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      await store.load(),
      const SuwayomiSettings(
        serverUrl: 'https://m.example.org',
        username: 'u',
        password: 'p',
      ),
    );
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('tests the typed values without saving them', (tester) async {
    await pump(tester);
    await tester.enterText(field('Server URL'), 'http://h');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(tested.single.serverUrl, 'http://h');
    expect(find.text('Connected: Suwayomi-Server v2.4.2366'), findsOneWidget);
    expect((await store.load()).isConfigured, isFalse);
  });

  testWidgets('shows why the connection failed', (tester) async {
    await pump(tester, test: (_) async => throw const SuwayomiAuthException());
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('Failed: wrong username or password'), findsOneWidget);
    await pump(tester, test: (_) async => throw StateError('offline'));
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed: Bad state: offline'), findsOneWidget);
  });

  testWidgets('opens the extensions screen', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Extensions'));
    expect(opened, 1);
  });

  testWidgets('Escape goes back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SuwayomiSettingsScreen(
                  store: store,
                  testConnection: (_) async => '',
                  onOpenExtensions: () {},
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SuwayomiSettingsScreen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SuwayomiSettingsScreen), findsNothing);
  });

  testWidgets('shows settings sync problems above the fields', (t) async {
    await pump(
      t,
      problems: Stream.value(["Couldn't decrypt synced Suwayomi password"]),
    );
    expect(
      find.text("Couldn't decrypt synced Suwayomi password"),
      findsOneWidget,
    );
  });
}
