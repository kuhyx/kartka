import 'package:kartka/app/feature.dart';
import 'package:kartka/backup_import/backup_import_feature.dart';
import 'package:kartka/library/library_repositories.dart';

/// Resolves the §8 repositories for an import from library's accessor, which
/// has already applied sync's decorators (so the import syncs).
ImportRepositories resolveRepositories(KartkaEnv env) {
  final repos = env.registry.maybe<LibraryRepositories>();
  if (repos == null) {
    throw StateError('Library repositories are not registered');
  }
  return (
    library: repos.library,
    categories: repos.categories,
    progress: repos.progress,
  );
}
