/// The [RepositoryDecorator] sync registers (contracts §13, §14): every repo
/// the library accessor hands out is wrapped so writes reach RTDB and remote
/// changes reach the local store, while the UI never knows sync exists.
library;

import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/library/repository_decorator.dart';
import 'package:kartka/sync/decorators/synced_categories.dart';
import 'package:kartka/sync/decorators/synced_library.dart';
import 'package:kartka/sync/decorators/synced_progress.dart';
import 'package:kartka/sync/sync_engine.dart';

/// Wraps the three synced repositories around one [SyncEngine].
class SyncRepositoryDecorator implements RepositoryDecorator {
  /// Creates the decorator. [engine] is called only when a repository is
  /// first wrapped (never while the registry is built), and its future
  /// completes once the device id and persisted shadow have loaded, so repos
  /// are handed out synchronously before that.
  new(this.engine);

  /// Starts (or returns) the engine.
  final Future<SyncEngine> Function() engine;

  @override
  LibraryRepository library(LibraryRepository inner) =>
      SyncedLibraryRepository(inner, engine());

  @override
  CategoryRepository categories(CategoryRepository inner) =>
      SyncedCategoryRepository(inner, engine());

  @override
  ProgressRepository progress(ProgressRepository inner) =>
      SyncedProgressRepository(inner, engine());
}
