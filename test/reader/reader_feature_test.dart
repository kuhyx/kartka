import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/reader_feature.dart';
import 'package:kartka/reader/ui/reader_screen.dart';

import 'support/fakes.dart';
import 'ui/reader_harness.dart';

void main() {
  late FakeKartkaHttp http;
  late MemoryKeyValueStore kv;
  late LibraryRepositories repos;
  late KartkaRegistry registry;
  late FakeReaderSystem system;

  setUp(() {
    http = FakeKartkaHttp(
      (r) => KartkaResponse(
        statusCode: 200,
        bodyBytes: onePixelPng,
        headers: const {},
      ),
    );
    kv = MemoryKeyValueStore();
    repos = LibraryRepositories(kv, decorators: () => []);
    system = FakeReaderSystem();
    final source = FakeSource(
      chapterList: harnessChapters,
      pageMap: {
        '/c/2': fakePages('/c/2', 2),
        '/c/3': fakePages('/c/3', 2),
      },
    );
    registry = KartkaRegistry.build(memoryPlatform(http: http, kv: kv), [
      (env) => readerFeature(env, system: system),
      (env) => KartkaFeature(
        id: 'test',
        services: [
          StaticSourceProvider([source]),
          repos,
        ],
      ),
    ]);
  });

  Future<void> pump(WidgetTester tester, String location) async {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        ...registry.routes,
        GoRoute(
          path: mangaRoutePattern,
          builder: (context, state) => const Text('manga page'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the route loads pages through KartkaHttp with page headers',
      (tester) async {
    await ReaderPrefs(kv).setModeFor('fake|/m/1', ReaderMode.pagedLtr);
    await pump(tester, readRoute('fake', '/m/1', '/c/2'));
    expect(find.byType(ReaderScreen), findsOneWidget);
    final first = http.requests.first;
    expect(first.url.toString(), 'https://img.test/c/2/0.png');
    expect(first.headers['Referer'], 'https://src.test/');
  });

  testWidgets('finishing a chapter records progress, marks read and opens '
      'the next one', (tester) async {
    await ReaderPrefs(kv).setModeFor('fake|/m/1', ReaderMode.pagedLtr);
    await pump(tester, readRoute('fake', '/m/1', '/c/2'));
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      for (var j = 0; j < 10; j++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    final saved = await repos.progress.watch('fake|/m/1').first;
    expect(saved?.chapterUrl, '/c/2');
    expect(saved?.page, 1);
    expect(await repos.progress.readChapters('fake|/m/1').first, {'/c/2'});
    await tester.tap(find.text('Next: Ch. 3'));
    for (var j = 0; j < 10; j++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(http.requests.last.url.path, startsWith('/c/3/'));
  });

  testWidgets('Escape with nothing to pop goes to the manga page',
      (tester) async {
    await pump(tester, readRoute('fake', '/m/1', '/c/2'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('manga page'), findsOneWidget);
  });

  testWidgets('the settings tile edits the global settings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: registry.settingsTiles.single),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('pages prefetched'), findsOneWidget);
    await tester.tap(find.text('Reader'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invert tap zones'));
    await tester.pumpAndSettle();
    expect((await ReaderPrefs(kv).settings()).invertTaps, isTrue);
  });
}
