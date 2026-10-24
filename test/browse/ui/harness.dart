import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/ui/global_search_screen.dart';
import 'package:kartka/browse/ui/manga_detail_screen.dart';
import 'package:kartka/browse/ui/source_screen.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/downloads/download_service.dart';

import '../fakes.dart';

/// A 1x1 transparent PNG, so covers decode in tests.
final onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Health port with fixed data and a text badge.
class FakeHealth implements SourceHealthLookup {
  const new(this.data);

  final Map<String, SourceHealthSummary> data;

  @override
  Stream<Map<String, SourceHealthSummary>> watch() => Stream.value(data);

  @override
  Widget? buildBadge(
    BuildContext context,
    String sourceId,
    SourceHealthSummary? summary,
  ) => summary == null ? null : Text('badge:${summary.verdict.name}');
}

/// Detail slot rendering a marker text.
class FakeSlot implements MangaDetailSlot {
  @override
  Widget build(BuildContext context, String key, MangaDetails details) =>
      Text('slot:$key');
}

/// Everything a widget test needs, wired to fakes.
class Harness {
  new({
    List<MangaSource>? sources,
    this.health,
    bool withDownloads = true,
    bool withCovers = true,
    this.downloadService,
  }) : provider = FakeSourceProvider() {
    final registry = SourceRegistry([
      StaticSourceProvider(sources ?? [FakeSource('mangadex')]),
      provider,
    ]);
    deps = BrowseDeps(
      sources: registry,
      chapters: ChapterStore(registry.byId),
      library: library,
      progress: progress,
      downloads: withDownloads ? (downloadService ?? downloads) : null,
      downloadService: downloadService,
      health: health,
      detailSlots: [FakeSlot()],
      coverLoader: withCovers ? (_) async => onePixelPng : null,
      clock: () => DateTime.utc(2026, 10, 24),
    );
  }

  final FakeSourceProvider provider;
  final SourceHealthLookup? health;
  final DownloadService? downloadService;
  final library = FakeLibrary();
  final progress = FakeProgress();
  final downloads = FakeDownloads();
  late final BrowseDeps deps;

  /// Pumps [home] at `/` inside a router that also knows the browse routes;
  /// the reader route renders `reader:<chapterUrl>`.
  Future<GoRouter> pump(
    WidgetTester tester,
    Widget home, {
    String at = '/',
    bool settle = true,
  }) {
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: home),
        ),
        GoRoute(
          path: mangaRoutePattern,
          builder: (_, s) {
            final r = parseMangaRoute(s.uri.path)!;
            return MangaDetailScreen(
              sourceId: r.sourceId,
              mangaUrl: r.mangaUrl,
            );
          },
        ),
        GoRoute(
          path: readRoutePattern,
          builder: (_, s) =>
              Text('reader:${parseReadRoute(s.uri.path)!.chapterUrl}'),
        ),
        GoRoute(
          path: sourceRoutePattern,
          builder: (_, s) => SourceScreen(
            s.pathParameters['sourceId']!,
            query: s.uri.queryParameters['q'],
          ),
        ),
        GoRoute(
          path: globalSearchRoutePattern,
          builder: (_, s) =>
              GlobalSearchScreen(query: s.uri.queryParameters['q'] ?? ''),
        ),
      ],
    );
    return tester
        .pumpWidget(
          BrowseScope(
            deps: deps,
            child: MaterialApp.router(
              theme: buildDarkTheme(),
              routerConfig: router,
            ),
          ),
        )
        .then((_) => settle ? tester.pumpAndSettle() : tester.pump())
        .then((_) => router);
  }
}
