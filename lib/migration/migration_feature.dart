import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/migration/better/better_wiring.dart';
import 'package:kartka/migration/dedupe/dedupe_wiring.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/migration/walk/page_previews.dart';
import 'package:kartka/platform/image_headers.dart';
import 'package:kartka/platform/page_image.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';
import 'package:kartka/tracking/common/tracking_service.dart';
import 'package:material_ui/material_ui.dart';

/// Route of the one-by-one migration of the whole library (More →
/// Migrate). The path keeps its old name: links to it stay valid.
const String migrateRoute = '/more/migrate-atsumaru';

/// [migrateRoute] walking only [keys] (the whole library when empty).
String migrateRouteFor(Iterable<MangaKey> keys) => Uri(
  path: migrateRoute,
  queryParameters: keys.isEmpty ? null : {'key': keys.toList()},
).toString();

/// The migration part: the one-by-one walk route, a More tile (the whole
/// library) and a manga-detail slot (that one entry); plus "Migrate to
/// better sources" (route and More tile: the entries that should move),
/// and the automatic duplicate merging (a library start task).
KartkaFeature migrationFeature(KartkaEnv env) => KartkaFeature(
  id: 'migration',
  routes: [
    GoRoute(
      path: migrateRoute,
      builder: (_, state) {
        final keys = state.uri.queryParametersAll['key'] ?? const [];
        return migrationWalk(
          env.registry,
          _deps(env),
          onlyKeys: keys.isEmpty ? null : keys.toSet(),
          pages: _pages(env),
        );
      },
    ),
    betterSourcesGoRoute(
      () => env.registry,
      () => _deps(env),
      pages: _pages(env),
    ),
  ],
  settingsTiles: [
    (context) => ListTile(
      leading: const Icon(
        Icons.swap_horiz,
        semanticLabel:
            'Migrate the library one by one. Move entries, progress, '
            'categories and trackers to the best source',
      ),
      onTap: () => unawaited(context.push(migrateRoute)),
    ),
    betterSourcesTile,
  ],
  services: [_MigrateSlot(env), libraryDeduper(env, () => _deps(env))],
);

MigrationDeps _deps(KartkaEnv env) {
  final registry = env.registry;
  final repos = registry.maybe<LibraryRepositories>()!;
  return MigrationDeps(
    library: repos.library,
    categories: repos.categories,
    progress: repos.progress,
    backups: env.platform.diagnostics,
    tracking: registry.maybe<TrackingService>(),
    chapterNumbers: registry.maybe<ChapterUrlResolver>(),
  );
}

/// "Migrate" on the detail screen of a library entry.
class _MigrateSlot implements MangaDetailSlot {
  const new(this._env);

  final KartkaEnv _env;

  @override
  void opened(MangaKey key) {}

  @override
  void loaded(MangaKey key, {String? firstUnread}) {}

  @override
  Widget build(BuildContext context, MangaKey key, MangaDetails details) =>
      _MigrateButton(
        library: _env.registry.maybe<LibraryRepositories>()!.library,
        mangaKey: key,
      );
}

/// Shown while [mangaKey] is in the library. Holds its stream, so a
/// rebuild of the detail screen does not resubscribe the repository.
class _MigrateButton extends StatefulWidget {
  const new({required this.library, required this.mangaKey});

  final LibraryRepository library;
  final MangaKey mangaKey;

  @override
  State<_MigrateButton> createState() => _MigrateButtonState();
}

class _MigrateButtonState extends State<_MigrateButton> {
  late final Stream<bool> _saved = widget.library.watch().map(
    (all) => all.any((e) => e.key == widget.mangaKey),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _saved,
    builder: (context, saved) => saved.data ?? false
        ? IconButton.outlined(
            style: IconButton.styleFrom(minimumSize: const Size.square(48)),
            icon: const Icon(Icons.swap_horiz, semanticLabel: 'Migrate'),
            onPressed: () =>
                unawaited(context.push(migrateRouteFor([widget.mangaKey]))),
          )
        : const SizedBox.shrink(),
  );
}

/// Page bytes for the walk's previews, as the reader loads them (headers
/// read from the finished registry at each load).
PageBytes _pages(KartkaEnv env) =>
    (page) => PageImageLoader(
      http: env.platform.http,
      blobs: env.platform.blobs,
      imageHeaders: env.registry.all<ImageHeaders>(),
      extensions: env.platform.extensions,
    ).load(page);
