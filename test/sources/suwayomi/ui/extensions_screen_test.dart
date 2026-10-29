import 'dart:convert';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';
import 'package:kartka/sources/suwayomi/ui/extensions_screen.dart';

import '../fakes.dart';

const _fixtures = ['extensions', 'ext_install', 'ext_update', 'ext_uninstall'];

void main() {
  late int changes;
  setUp(() => changes = 0);

  SuwayomiExtensionsApi api(
    FakeKartkaHttp http, [
    SuwayomiSettings settings = fixtureSettings,
  ]) => SuwayomiExtensionsApi(
    client: SuwayomiClient(http: http, settings: () => settings),
    settings: () => settings,
    onChanged: () async => changes++,
  );

  Future<void> pump(
    WidgetTester tester,
    SuwayomiExtensionsApi api, {
    DiagnosticsLog? log,
  }) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: ExtensionsScreen(api: api, diagnostics: log),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists installed and available extensions', (tester) async {
    await pump(tester, api(fixtureHttp(_fixtures)));
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('MangaDex'), findsOneWidget);
    expect(find.text('Weeb Central'), findsOneWidget);
    expect(find.text('Uninstall'), findsOneWidget);
    expect(find.text('Install'), findsWidgets);
  });

  testWidgets('section headers keep the screen gutter', (tester) async {
    await pump(tester, api(fixtureHttp(_fixtures)));
    for (final header in ['Installed', 'Available']) {
      expect(
        tester.getTopLeft(find.text(header)).dx,
        greaterThanOrEqualTo(AppSpacing.md),
        reason: header,
      );
    }
  });

  testWidgets('filters by name or language', (tester) async {
    await pump(tester, api(fixtureHttp(_fixtures)));
    await tester.enterText(find.byType(TextField), 'weeb');
    await tester.pumpAndSettle();
    expect(find.text('Weeb Central'), findsOneWidget);
    expect(find.text('MangaDex'), findsNothing);
    expect(find.text('Installed'), findsNothing);
  });

  testWidgets('installs and moves the extension to installed', (tester) async {
    final http = fixtureHttp(_fixtures);
    await pump(tester, api(http));
    await tester.enterText(find.byType(TextField), 'weeb');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(changes, 1);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Uninstall'), findsOneWidget);
    expect(find.text('Installed Weeb Central'), findsOneWidget);
  });

  testWidgets('uninstall asks first', (tester) async {
    await pump(tester, api(fixtureHttp(_fixtures)));
    await tester.tap(find.text('Uninstall'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changes, 0);
  });

  testWidgets('a failed action shows an error', (tester) async {
    // MangaDex uninstall has no fixture, so the fake answers 599.
    await pump(tester, api(fixtureHttp(['extensions'])));
    await tester.tap(find.text('Uninstall'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uninstall').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 599'), findsOneWidget);
    expect(changes, 0);
  });

  testWidgets('offers update when the store has a newer build', (tester) async {
    final http = FakeKartkaHttp(
      (_) => FakeKartkaHttp.text(
        '{"data":{"fetchExtensions":{"extensions":[{"pkgName":"p",'
        '"name":"Old","lang":"en","versionName":"1","iconUrl":"/i",'
        '"isInstalled":true,"hasUpdate":true,"isObsolete":true}]}}}',
      ),
    );
    await pump(tester, api(http));
    expect(find.text('Update'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // toast expires
    await tester.pumpAndSettle();
    expect(find.textContaining('update available'), findsOneWidget);
    expect(find.textContaining('obsolete'), findsOneWidget);
  });

  testWidgets('explains an empty store list', (tester) async {
    final http = FakeKartkaHttp(
      (_) =>
          FakeKartkaHttp.text('{"data":{"fetchExtensions":{"extensions":[]}}}'),
    );
    await pump(tester, api(http));
    expect(find.text('No extensions'), findsOneWidget);
  });

  testWidgets('shows load errors with a retry', (tester) async {
    final log = DiagnosticsLog(MemoryBlobStore());
    await pump(
      tester,
      api(FakeKartkaHttp(), const SuwayomiSettings()),
      log: log,
    );
    expect(find.text("Can't list extensions"), findsOneWidget);
    final logged = (await tester.runAsync(log.entries))!.single;
    expect(logged.kind, 'suwayomi.extensions');
    expect(logged.error, contains('no server URL'));
    expect(find.textContaining('no server URL'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('updates and uninstalls, then Escape goes back', (tester) async {
    String ext(String pkg, String name) =>
        '{"pkgName":"eu.kanade.tachiyomi.extension.$pkg","name":"$name",'
        '"lang":"en","versionName":"1","iconUrl":"/i","isInstalled":true,'
        '"hasUpdate":true,"isObsolete":false}';
    String body(String name) => jsonEncode(fixture(name)['response']);
    final http = FakeKartkaHttp((r) {
      final req = jsonDecode(r.body!) as Map<String, Object?>;
      final patch = (req['variables']! as Map)['patch'] as Map?;
      return FakeKartkaHttp.text(switch (patch?.keys.single) {
        null =>
          '{"data":{"fetchExtensions":{"extensions":['
              '${ext('all.mangadex', 'MangaDex')},'
              '${ext('en.weebcentral', 'Weeb Central')}]}}}',
        'update' => body('ext_update'),
        _ => body('ext_uninstall'),
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExtensionsScreen(api: api(http)),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update').first);
    await tester.pumpAndSettle();
    expect(find.text('Updated MangaDex'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Weeb Central'),
        matching: find.text('Uninstall'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uninstall').last);
    await tester.pumpAndSettle();
    expect(find.text('Uninstalled Weeb Central'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(changes, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ExtensionsScreen), findsNothing);
  });
}
