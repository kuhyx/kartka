import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/backup_import/backup_importer.dart';
import 'package:kartka/backup_import/import_controller.dart';
import 'package:kartka/backup_import/import_screen.dart';
import 'package:kartka/backup_import/repositories_seam.dart';
import 'package:kartka/backup_import/tracker_binding_sink.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/source_provider.dart';

/// Route of the import screen (More → Import SY backup).
const String importSyBackupRoute = '/more/import-sy-backup';

/// The three repositories an import writes through (§8).
typedef ImportRepositories = ({
  LibraryRepository library,
  CategoryRepository categories,
  ProgressRepository progress,
});

/// How repositories are obtained (see [resolveRepositories]).
typedef ImportRepositoriesResolver = ImportRepositories Function(KartkaEnv env);

/// Builds the importer for [env]; tracker bindings go to a tracking-supplied
/// [TrackerBindingSink] service, and are skipped when none is registered.
BackupImporter buildImporter(
  KartkaEnv env,
  ImportRepositoriesResolver resolve,
) {
  final repos = resolve(env);
  return BackupImporter(
    library: repos.library,
    categories: repos.categories,
    progress: repos.progress,
    bindings: env.registry.maybe<TrackerBindingSink>(),
  );
}

/// Ids of every source that can be opened right now, or null when no
/// [SourceProvider] is registered (availability unknown).
Future<Set<String>?> availableSourceIds(KartkaEnv env) async {
  final providers = env.registry.all<SourceProvider>();
  if (providers.isEmpty) return null;
  return {
    for (final p in providers)
      for (final source in await p.watch().first) source.ref.id,
  };
}

/// The backup-import feature: one route plus a tile in More.
KartkaFeature backupImportFeatureWith(
  KartkaEnv env,
  ImportRepositoriesResolver resolve,
) => KartkaFeature(
  id: 'backup_import',
  routes: [
    GoRoute(
      path: importSyBackupRoute,
      builder: (context, state) => ImportScreen(
        controller: ImportController(
          picker: env.platform.filePicker,
          importer: buildImporter(env, resolve),
          availableSources: () => availableSourceIds(env),
        ),
      ),
    ),
  ],
  settingsTiles: [
    (context) => ListTile(
      leading: const Icon(Icons.file_upload_outlined),
      title: const Text('Import SY backup'),
      subtitle: const Text('Library, categories, progress and trackers'),
      onTap: () => context.push(importSyBackupRoute),
    ),
  ],
);

/// Registry entry point (`backupImportFeature,` in `kartkaFeatureFactories`).
KartkaFeature backupImportFeature(KartkaEnv env) =>
    backupImportFeatureWith(env, resolveRepositories);
