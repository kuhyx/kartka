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
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';

import 'fake_download_service.dart';
import 'fakes.dart';
import 'ui/harness.dart';

KartkaRegistry _registry({
  bool withLibrary = true,
  FakeDownloadService? downloads,
  MemoryKeyValueStore? store,
}) {
  final kv = store ?? MemoryKeyValueStore();
  final http = FakeKartkaHttp(
    (_) => KartkaResponse(statusCode: 200, bodyBytes: onePixelPng),
  );
  return KartkaRegistry.build(memoryPlatform(http: http, kv: kv), [
    (_) => KartkaFeature(
      id: 'fixtures',
      services: [
        StaticSourceProvider([FakeSource('mangadex', name: 'MangaDex')]),
        if (withLibrary) LibraryRepositories(kv, decorators: () => const []),
        ?downloads,
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

  testWidgets('the tab reads browse.languages from the platform kv', (t) async {
    final kv = MemoryKeyValueStore({'browse.languages': '["ko"]'});
    await _pumpApp(t, _registry(store: kv), '/');
    expect(find.text('MangaDex'), findsNothing);
    expect(find.text('No sources in your languages'), findsOneWidget);
  });

  testWidgets('detail route decodes its params and loads covers', (t) async {
    await _pumpApp(t, _registry(), mangaRoute('mangadex', '/m/1?x=1'));
    expect(find.text('Detail title'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('a registered DownloadService reaches the chapter rows', (
    t,
  ) async {
    final downloads = FakeDownloadService()
      ..states['/c/1'] = const DownloadState(status: DownloadStatus.done);
    await _pumpApp(
      t,
      _registry(downloads: downloads),
      mangaRoute('mangadex', '/m/1'),
    );
    await t.tap(find.byTooltip('Delete download'));
    await t.pumpAndSettle();
    expect(downloads.calls, ['delete:/c/1']);
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
    final resolver = reg.maybe<ChapterUrlResolver>()!;
    expect(await resolver.resolve(key, 2), '/c/2');
    final port = reg.maybe<BrowseResolverPort>()!;
    expect(await port.numberOf(key, '/c/3'), 3);
    expect(await counts.watch(key).first, 3);
  });

  testWidgets('without the library feature the tab fails loudly', (t) async {
    final tab = _registry(withLibrary: false).tab(KartkaTab.browse)!;
    await t.pumpWidget(Builder(builder: tab));
    expect('${t.takeException()}', contains('library'));
  });
}
