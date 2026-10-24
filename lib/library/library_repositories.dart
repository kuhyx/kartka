import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/library/data/local_category_repository.dart';
import 'package:kartka/library/data/local_library_repository.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/library/repository_decorator.dart';
import 'package:kartka/platform/key_value_store.dart';

/// The one place other parts get repositories from (contracts §13, §14).
///
/// Registered in the library feature's services; consumers call
/// `registry.maybe<LibraryRepositories>()`. Each getter builds the local
/// implementation on first use and wraps it with every
/// [RepositoryDecorator] in registry order (the first decorator is the
/// innermost), so sync stays invisible to callers.
class LibraryRepositories {
  /// Creates the accessor over `store`; `decorators` is read lazily because
  /// the registry is only complete after every feature factory ran.
  new(this._store, {required this._decorators, this._now});

  final KeyValueStore _store;
  final List<RepositoryDecorator> Function() _decorators;
  final DateTime Function()? _now;

  /// The library entries.
  late final LibraryRepository library = _decorate(
    LocalLibraryRepository(_store, now: _now),
    (d, inner) => d.library(inner),
  );

  /// Categories and membership.
  late final CategoryRepository categories = _decorate(
    LocalCategoryRepository(_store, now: _now),
    (d, inner) => d.categories(inner),
  );

  /// Reading progress and read marks.
  late final ProgressRepository progress = _decorate(
    LocalProgressRepository(_store, now: _now),
    (d, inner) => d.progress(inner),
  );

  T _decorate<T>(T local, T Function(RepositoryDecorator d, T inner) wrap) =>
      _decorators().fold(local, (inner, d) => wrap(d, inner));
}
