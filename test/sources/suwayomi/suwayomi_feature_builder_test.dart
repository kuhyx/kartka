import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/image_headers.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/suwayomi_feature_builder.dart';
import 'package:kartka/sources/suwayomi/ui/extensions_screen.dart';

import 'fakes.dart';

const _url = 'http://127.0.0.1:4599/';

void main() {
  final asked = <MangaKey>[];

  KartkaRegistry registry() {
    asked.clear();
    final platform = memoryPlatform(
      http: fixtureHttp([
        'about',
        'sources',
        'extensions',
        'manga_id_unseen',
        'search',
        'details_unseen',
      ]),
      kv: MemoryKeyValueStore({'suwayomi.serverUrl': _url}),
      secrets: MemoryKeyValueStore({
        'suwayomi.username': 'kartka',
        'suwayomi.password': 'fixture',
      }),
    );
    return KartkaRegistry.build(platform, [
      (env) => buildSuwayomiFeature(
        env,
        titleOf: (key) async {
          asked.add(key);
          return 'Sousou no Frieren';
        },
      ),
    ]);
  }

  test('supplies the source provider and the image headers', () async {
    final r = registry();
    final sources = await r.all<SourceProvider>().single.watch().first;
    expect(sources, hasLength(2));
    final headers = r.all<ImageHeaders>().single;
    expect(headers.forUrl('${_url}api/v1/manga/1/thumbnail'), isNotEmpty);
    expect(headers.forUrl('https://elsewhere/x'), isEmpty);
  });

  test('unseen manga are searched by the injected title lookup', () async {
    final r = registry();
    const url = '/manga/b0b721ff-c388-4486-aa0f-c2b0bb321512';
    const sourceId = 'suwayomi:$mangadexEn';
    final sources = await r.all<SourceProvider>().single.watch().first;
    final source = sources.firstWhere((s) => s.ref.id == sourceId);
    expect((await source.details(url)).url, url);
    expect(asked, [mangaKeyOf(sourceId, url)]);
  });

  testWidgets('settings tile opens settings, then extensions', (tester) async {
    final r = registry();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: ListView(
              children: [for (final t in r.settingsTiles) t(context)],
            ),
          ),
        ),
        ...r.routes,
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: buildDarkTheme(), routerConfig: router),
    );
    await tester.tap(find.text('Suwayomi server'));
    await tester.pumpAndSettle();
    expect(find.text(_url), findsOneWidget);
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('Connected: Suwayomi-Server v2.4.2366'), findsOneWidget);
    await tester.tap(find.text('Extensions'));
    await tester.pumpAndSettle();
    expect(find.byType(ExtensionsScreen), findsOneWidget);
    expect(find.text('MangaDex'), findsOneWidget);
  });
}
