import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/download_repository.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/downloads/downloads_feature.dart';
import 'package:kartka/downloads/keys.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/platform.dart';

import 'fakes.dart';
import 'service_harness.dart';

KartkaFeature _extras(KartkaEnv env) => KartkaFeature(
  id: 'test-extras',
  services: [
    StaticSourceProvider([FakeSource()]),
    LibraryRepositories(env.platform.kv, decorators: () => const []),
  ],
);

void main() {
  late KartkaPlatform platform;
  late KartkaRegistry registry;

  setUp(() {
    final http = FakeKartkaHttp(
      (r) => KartkaResponse(
        statusCode: 200,
        bodyBytes: Uint8List.fromList(fakeImage(r.url.toString())),
      ),
    );
    platform = memoryPlatform(http: http);
    registry = KartkaRegistry.build(platform, [downloadsFeature, _extras]);
  });

  test('supplies DownloadRepository and DownloadedLookup', () async {
    final repo = registry.maybe<DownloadRepository>()!;
    expect(registry.maybe<DownloadedLookup>(), same(repo));
    await repo.enqueue(mangaKey, ch1);
    final pages = await repo
        .watch(mangaKey, ch1.url)
        .firstWhere((s) => s.status == DownloadStatus.done)
        .then((_) => repo.offlinePages(mangaKey, ch1.url));
    final first = fixturePages().first;
    expect(
      await platform.pageImages(registry).load(pages!.first),
      fakeImage(first.imageUrl),
    );
    expect(await platform.kv.get(autoLastCheckKvKey), isNotNull);
  });

  test('works without a library part (auto check sees no manga)', () async {
    final bare = KartkaRegistry.build(platform, [downloadsFeature]);
    await platform.kv.set(autoDownloadKvKey, 'true');
    final repo = bare.maybe<DownloadRepository>()!;
    expect(await repo.offlinePages(mangaKey, ch1.url), isNull);
    await pumpEventQueue();
    expect(await platform.kv.get(autoLastCheckKvKey), isNotNull);
  });

  testWidgets('More tiles open the Downloads screen; auto switch persists', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: ListView(
              children: [for (final t in registry.settingsTiles) t(context)],
            ),
          ),
        ),
        ...registry.routes,
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: buildDarkTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    expect(find.text('Auto-download new chapters'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(await platform.kv.get(autoDownloadKvKey), 'true');

    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('No downloads'), findsOneWidget);
    expect(downloadsRoutePath, '/downloads');
  });
}

extension on KartkaPlatform {
  PageImageLoader pageImages(KartkaRegistry r) => PageImageLoader(
    http: http,
    blobs: blobs,
    imageHeaders: r.all<ImageHeaders>(),
  );
}
