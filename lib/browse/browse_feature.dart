import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/app/settings_stores.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/browse/ports/browse_chapter_url_resolver.dart';
import 'package:kartka/browse/ports/browse_unread_counts.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/browse/state/chapter_sort_store.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/detail_store.dart';
import 'package:kartka/browse/state/shared_health_lookup.dart';
import 'package:kartka/browse/ui/browse_tab.dart';
import 'package:kartka/browse/ui/global_search_screen.dart';
import 'package:kartka/browse/ui/manga_detail_screen.dart';
import 'package:kartka/browse/ui/source_screen.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/updates/chapter_addition_sink.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/downloads/download_service.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/platform/cover_cache.dart';
import 'package:kartka/platform/image_headers.dart';
import 'package:kartka/platform/page_image.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';

/// The browse part: Browse tab, source/search/detail routes, and the
/// unread-count, chapter-url and [ChapterUpdateChecker] ports other parts
/// consume.
KartkaFeature browseFeature(KartkaEnv env) {
  final runtime = BrowseRuntime(env);
  return KartkaFeature(
    id: 'browse',
    tabs: {KartkaTab.browse: (_) => runtime.scoped(const BrowseTab())},
    routes: [
      GoRoute(
        path: mangaRoutePattern,
        builder: (_, state) {
          final r = parseMangaRoute(state.uri.path)!;
          return runtime.scoped(
            MangaDetailScreen(sourceId: r.sourceId, mangaUrl: r.mangaUrl),
          );
        },
      ),
      GoRoute(
        path: sourceRoutePattern,
        builder: (_, state) => runtime.scoped(
          SourceScreen(
            state.pathParameters['sourceId']!,
            query: state.uri.queryParameters['q'],
          ),
        ),
      ),
      GoRoute(
        path: globalSearchRoutePattern,
        builder: (_, state) => runtime.scoped(
          GlobalSearchScreen(query: state.uri.queryParameters['q'] ?? ''),
        ),
      ),
    ],
    services: [
      _LazyUnreadCounts(runtime),
      BrowseResolverPort(runtime),
      _LazyUpdateChecker(runtime),
    ],
  );
}

/// Browse's long-lived objects, built on first use: `env.registry` is only
/// valid after every feature factory ran.
class BrowseRuntime {
  /// Creates the runtime over [_env].
  new(this._env);

  final KartkaEnv _env;

  /// Live source list.
  late final SourceRegistry sources = SourceRegistry.fromRegistry(
    _env.registry,
  );

  /// The Browse language selection, synced across devices.
  late final BrowseLanguageStore languages = () {
    final kv = syncedKv(_env);
    return BrowseLanguageStore(kv, reloadOn: kv.remoteChanges);
  }();

  /// Persistent chapter cache; every list it grows is told to each
  /// [ChapterAdditionSink] (the updates feed), looked up at call time.
  late final ChapterStore chapters = ChapterStore(
    sources.byId,
    kv: _env.platform.kv,
    onAdded: (key, added) {
      for (final sink in _env.registry.all<ChapterAdditionSink>()) {
        sink.record(key, added).ignore();
      }
    },
  );

  late final LibraryRepositories _repos =
      _env.registry.maybe<LibraryRepositories>() ??
      (throw StateError('browse needs the library feature registered'));

  // The library's shared cover cache (one fetch per cover across both
  // grids); a private one when the library did not register it.
  late final CoverCache _covers =
      _env.registry.maybe<CoverCache>() ??
      CoverCache(
        load: (url) => PageImageLoader(
          http: _env.platform.http,
          blobs: _env.platform.blobs,
          imageHeaders: _env.registry.all<ImageHeaders>(),
        ).load(PageRef(index: 0, imageUrl: url)),
        store: _env.platform.cache,
      );

  // One health subscription for every Browse mount (see SharedHealthLookup).
  late final SourceHealthLookup? _health = switch (_env.registry
      .maybe<SourceHealthLookup>()) {
    final inner? => SharedHealthLookup(inner),
    null => null,
  };

  /// Dependencies of every browse screen.
  late final BrowseDeps deps = BrowseDeps(
    sources: sources,
    languages: languages,
    chapters: chapters,
    library: _repos.library,
    progress: _repos.progress,
    downloads: _env.registry.maybe<DownloadRepository>(),
    downloadService: _env.registry.maybe<DownloadService>(),
    health: _health,
    detailSlots: _env.registry.all<MangaDetailSlot>(),
    coverLoader: _covers.get,
    browser: _env.platform.browser,
    diagnostics: DiagnosticsLog.of(_env.platform.diagnostics),
    details: DetailStore(_env.platform.kv),
    chapterSort: () {
      final kv = syncedKv(_env);
      return ChapterSortStore(kv, reloadOn: kv.remoteChanges);
    }(),
  );

  /// The unread-count port implementation.
  late final unreadCounts = BrowseUnreadCounts(chapters, _repos.progress);

  /// The chapter-url port implementation.
  late final resolver = BrowseChapterUrlResolver(chapters);

  /// [child] under a [BrowseScope] with [deps].
  Widget scoped(Widget child) => BrowseScope(deps: deps, child: child);
}

class _LazyUnreadCounts implements UnreadCounts {
  const new(this._runtime);

  final BrowseRuntime _runtime;

  @override
  Stream<int?> watch(String key) => _runtime.unreadCounts.watch(key);
}

class _LazyUpdateChecker implements ChapterUpdateChecker {
  const new(this._runtime);

  final BrowseRuntime _runtime;

  @override
  Future<UpdateResult> check(MangaKey key) => _runtime.deps.updates.check(key);
}

/// Tracking's chapter-url port, resolved lazily through [BrowseRuntime].
class BrowseResolverPort implements ChapterUrlResolver {
  /// Creates the port over [_runtime].
  const new(this._runtime);

  final BrowseRuntime _runtime;

  @override
  Future<String?> resolve(MangaKey key, int chapterNumber) =>
      _runtime.resolver.resolve(key, chapterNumber);

  @override
  Future<double?> numberOf(MangaKey key, String chapterUrl) =>
      _runtime.resolver.numberOf(key, chapterUrl);
}
