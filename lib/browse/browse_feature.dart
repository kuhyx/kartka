import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/browse/ports/browse_chapter_url_resolver.dart';
import 'package:kartka/browse/ports/browse_unread_counts.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/ui/browse_tab.dart';
import 'package:kartka/browse/ui/global_search_screen.dart';
import 'package:kartka/browse/ui/manga_detail_screen.dart';
import 'package:kartka/browse/ui/source_screen.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/platform/image_headers.dart';
import 'package:kartka/platform/page_image.dart';

/// The browse part: Browse tab, source/search/detail routes, and the
/// unread-count + chapter-url ports other parts consume.
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
    services: [_LazyUnreadCounts(runtime), _LazyResolver(runtime)],
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

  /// Persistent chapter cache.
  late final ChapterStore chapters = ChapterStore(
    sources.byId,
    kv: _env.platform.kv,
  );

  late final LibraryRepositories _repos =
      _env.registry.maybe<LibraryRepositories>() ??
      (throw StateError('browse needs the library feature registered'));

  late final _covers = PageImageLoader(
    http: _env.platform.http,
    blobs: _env.platform.blobs,
    imageHeaders: _env.registry.all<ImageHeaders>(),
  );

  /// Dependencies of every browse screen.
  late final BrowseDeps deps = BrowseDeps(
    sources: sources,
    chapters: chapters,
    library: _repos.library,
    progress: _repos.progress,
    downloads: _env.registry.maybe<DownloadRepository>(),
    health: _env.registry.maybe<SourceHealthLookup>(),
    detailSlots: _env.registry.all<MangaDetailSlot>(),
    coverLoader: (url) => _covers.load(PageRef(index: 0, imageUrl: url)),
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

// ADAPTER: implement tracking's `ChapterUrlResolver`
// (lib/tracking/common/chapter_url_resolver.dart) once agent/tracking-anilist
// commits it; until then this has the port's exact method shape.
class _LazyResolver {
  const new(this._runtime);

  final BrowseRuntime _runtime;

  Future<String?> resolve(MangaKey key, int chapterNumber) =>
      _runtime.resolver.resolve(key, chapterNumber);
}
