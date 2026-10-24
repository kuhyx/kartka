import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/browse_feature.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import 'fakes.dart';
import 'ui/harness.dart';

KartkaRegistry _registry({bool withLibrary = true}) {
  final kv = MemoryKeyValueStore();
  final http = FakeKartkaHttp(
    (_) => KartkaResponse(statusCode: 200, bodyBytes: onePixelPng),
  );
  return KartkaRegistry.build(memoryPlatform(http: http, kv: kv), [
    (_) => KartkaFeature(
      id: 'fixtures',
      services: [
        StaticSourceProvider([FakeSource('mangadex', name: 'MangaDex')]),
        if (withLibrary) LibraryRepositories(kv, decorators: () => const []),
      ],
    ),
    browseFeature,
  ]);
}

Future<void> _pumpApp(WidgetTester t, KartkaRegistry reg, String at) async {
  final tab = reg.tab(KartkaTab.browse)!;
  final router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(body: tab(context)),
      ),
      ...reg.routes,
      GoRoute(
        path: readRoutePattern,
        builder: (_, s) => Text('reader:${s.pathParameters['chapterUrl']}'),
      ),
    ],
  );
  await t.pumpWidget(MaterialApp.router(routerConfig: router));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('tab lists registered sources', (t) async {
    await _pumpApp(t, _registry(), '/');
    expect(find.text('MangaDex'), findsOneWidget);
  });

  testWidgets('detail route decodes its params and loads covers', (t) async {
    await _pumpApp(t, _registry(), mangaRoute('mangadex', '/m/1?x=1'));
    expect(find.text('Detail title'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('source and global search routes', (t) async {
    final reg = _registry();
    await _pumpApp(t, reg, sourceRoute('mangadex', query: 'q'));
    expect(find.text('Popular'), findsOneWidget);
    await _pumpApp(t, reg, globalSearchRoute('q'));
    expect(find.text('MangaDex'), findsOneWidget);
  });

  test('supplies UnreadCounts and the chapter-url resolver', () async {
    final reg = _registry();
    final key = mangaKeyOf('mangadex', '/m/1');
    final counts = reg.maybe<UnreadCounts>()!;
    expect(await counts.watch(key).first, isNull);
    final resolver = reg.maybe<BrowseResolverPort>()!;
    expect(await resolver.resolve(key, 2), '/c/2');
    expect(await counts.watch(key).first, 3);
  });

  testWidgets('without the library feature the tab fails loudly', (t) async {
    final reg = _registry(withLibrary: false);
    final tab = reg.tab(KartkaTab.browse)!;
    late Object error;
    await t.pumpWidget(
      Builder(
        builder: (context) {
          try {
            return tab(context);
          } on StateError catch (e) {
            error = e;
            return const SizedBox();
          }
        },
      ),
    );
    expect('$error', contains('library'));
  });
}
