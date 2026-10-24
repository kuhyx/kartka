import 'package:kartka/core/repositories/repositories.dart';

/// Wraps the local repositories (contracts §8, §10).
///
/// Sync supplies one through `KartkaFeature.services`; the library feature's
/// `LibraryRepositories` accessor applies every registered decorator in
/// registry order, so the UI and other parts never know sync exists.
abstract interface class RepositoryDecorator {
  /// Wraps the library repository.
  LibraryRepository library(LibraryRepository inner);

  /// Wraps the category repository.
  CategoryRepository categories(CategoryRepository inner);

  /// Wraps the progress repository.
  ProgressRepository progress(ProgressRepository inner);
}
