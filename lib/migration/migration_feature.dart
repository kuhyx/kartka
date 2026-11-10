import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/migration/better/better_wiring.dart';
import 'package:kartka/migration/migration_controller.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/migration/migration_screen.dart';
import 'package:kartka/migration/migration_target.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';
import 'package:kartka/tracking/common/tracking_service.dart';

/// Route of the review screen (More → Migrate to Atsumaru).
const String migrateRoute = '/more/migrate-atsumaru';

/// [migrateRoute] reviewing only [keys] (all entries when empty).
String migrateRouteFor(Iterable<MangaKey> keys) => Uri(
  path: migrateRoute,
  queryParameters: keys.isEmpty ? null : {'key': keys.toList()},
).toString();

/// The migration part: the review route, a More tile (the whole library)
/// and a manga-detail slot (that one entry); plus "Migrate to better
/// sources" (route and More tile).
KartkaFeature migrationFeature(KartkaEnv env) => KartkaFeature(
  id: 'migration',
  routes: [
    GoRoute(
      path: migrateRoute,
      builder: (_, state) {
        final keys = state.uri.queryParametersAll['key'] ?? const [];
        return MigrationScreen(
          controller: MigrationController(
            _deps(env),
            onlyKeys: keys.isEmpty ? null : keys.toSet(),
          ),
        );
      },
    ),
    betterSourcesGoRoute(() => env.registry, () => _deps(env)),
  ],
  settingsTiles: [
    (context) => ListTile(
      leading: const Icon(
        Icons.swap_horiz,
        semanticLabel:
            'Migrate to Atsumaru. Move entries, progress, categories '
            'and trackers',
      ),
      onTap: () => unawaited(context.push(migrateRoute)),
    ),
    betterSourcesTile,
  ],
  services: [_MigrateSlot(env)],
);

MigrationDeps _deps(KartkaEnv env) {
  final registry = env.registry;
  final repos = registry.maybe<LibraryRepositories>()!;
  return MigrationDeps(
    library: repos.library,
    categories: repos.categories,
    progress: repos.progress,
    findTarget: () => findTarget(registry.all<SourceProvider>()),
    backups: env.platform.diagnostics,
    tracking: registry.maybe<TrackingService>(),
    chapterNumbers: registry.maybe<ChapterUrlResolver>(),
  );
}

/// "Migrate" on the detail screen of a library entry not on Atsumaru.
class _MigrateSlot implements MangaDetailSlot {
  const new(this._env);

  final KartkaEnv _env;

  @override
  void opened(MangaKey key) {}

  @override
  Widget build(BuildContext context, MangaKey key, MangaDetails details) {
    if (details.sourceId == atsumaruSourceId) return const SizedBox.shrink();
    return _MigrateButton(
      library: _env.registry.maybe<LibraryRepositories>()!.library,
      mangaKey: key,
    );
  }
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
