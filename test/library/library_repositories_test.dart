import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/library/data/local_category_repository.dart';
import 'package:kartka/library/data/local_library_repository.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/repository_decorator.dart';

import 'support/memory_kv.dart';

abstract class _Tagged {
  new(this.tag, this.inner);
  final String tag;
  final Object inner;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Lib extends _Tagged implements LibraryRepository {
  new(super.tag, super.inner);
}

class _Cat extends _Tagged implements CategoryRepository {
  new(super.tag, super.inner);
}

class _Prog extends _Tagged implements ProgressRepository {
  new(super.tag, super.inner);
}

class _Decorator implements RepositoryDecorator {
  new(this.tag);
  final String tag;
  @override
  LibraryRepository library(LibraryRepository inner) => _Lib(tag, inner);
  @override
  CategoryRepository categories(CategoryRepository inner) => _Cat(tag, inner);
  @override
  ProgressRepository progress(ProgressRepository inner) => _Prog(tag, inner);
}

void main() {
  test('without decorators the local implementations are returned', () {
    final repos = LibraryRepositories(MemoryKv(), decorators: () => []);
    expect(repos.library, isA<LocalLibraryRepository>());
    expect(repos.categories, isA<LocalCategoryRepository>());
    expect(repos.progress, isA<LocalProgressRepository>());
    expect(repos.library, same(repos.library));
  });

  test('decorators wrap in registry order, built lazily once', () {
    var asked = 0;
    final repos = LibraryRepositories(
      MemoryKv(),
      decorators: () {
        asked++;
        return [_Decorator('first'), _Decorator('second')];
      },
    );
    expect(asked, 0);
    for (final repo in <Object>[
      repos.library,
      repos.categories,
      repos.progress,
    ]) {
      final outer = repo as _Tagged;
      expect(outer.tag, 'second');
      expect((outer.inner as _Tagged).tag, 'first');
    }
    expect(repos.progress, same(repos.progress));
    expect(asked, 3);
  });

  test('repositories share the one store', () async {
    final kv = MemoryKv();
    final repos = LibraryRepositories(kv, decorators: () => []);
    await repos.library.upsert(
      LibraryEntry(
        key: 's|/m',
        sourceId: 's',
        mangaUrl: '/m',
        title: 'm',
        addedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    expect(kv.data.keys.single, startsWith('library/'));
  });
}
