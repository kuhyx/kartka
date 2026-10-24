import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/library_routes.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/library/repository_decorator.dart';
import 'package:kartka/library/state/library_deps.dart';
import 'package:kartka/library/ui/categories_screen.dart';
import 'package:kartka/library/ui/library_screen.dart';
import 'package:kartka/platform/platform.dart';

/// The library part: the Library tab, category management, and the one
/// [LibraryRepositories] accessor every other part takes repositories from.
KartkaFeature libraryFeature(KartkaEnv env) {
  final platform = env.platform;
  final repos = LibraryRepositories(
    platform.kv,
    decorators: () => env.registry.all<RepositoryDecorator>(),
  );
  LibraryDeps? cached;
  // Built on first use: the registry is complete only after every factory.
  LibraryDeps deps() => cached ??= _deps(env, repos);
  return KartkaFeature(
    id: 'library',
    services: [repos],
    tabs: {KartkaTab.library: (_) => LibraryScreen(deps: deps())},
    routes: [
      GoRoute(
        path: libraryCategoriesRoute,
        builder: (_, _) => CategoriesScreen(deps: deps()),
      ),
    ],
  );
}

LibraryDeps _deps(KartkaEnv env, LibraryRepositories repos) {
  final registry = env.registry;
  final images = PageImageLoader(
    http: env.platform.http,
    blobs: env.platform.blobs,
    imageHeaders: registry.all<ImageHeaders>(),
  );
  return LibraryDeps(
    repos: repos,
    unread: registry.maybe<UnreadCounts>() ?? const NoUnreadCounts(),
    downloaded:
        registry.maybe<DownloadedLookup>() ?? const NoDownloadedLookup(),
    tracked: registry.maybe<TrackedLookup>() ?? const NoTrackedLookup(),
    sourceProviders: registry.all<SourceProvider>(),
    coverLoader: (url) => images.load(PageRef(index: 0, imageUrl: url)),
  );
}
