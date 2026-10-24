import 'dart:math';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/library/state/library_deps.dart';

/// Create, rename, reorder and delete categories.
///
/// Every write is stamped past the row it replaces ([nextStamp]), so an edit
/// made on a device whose clock lags still wins over what it saw.
class CategoryActions {
  /// Creates the actions; [newId] defaults to a random 128-bit hex id.
  new(this.deps, {String Function()? newId}) : newId = newId ?? _randomId;

  /// Repositories and clock.
  final LibraryDeps deps;

  /// Id generator for new categories.
  final String Function() newId;

  /// Adds a category named [name] after [existing]; blank names are ignored.
  Future<void> create(String name, List<Category> existing) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final order = existing.fold(-1, (m, c) => max(m, c.order)) + 1;
    await deps.repos.categories.upsert(
      Category(
        id: newId(),
        name: trimmed,
        order: order,
        updatedAt: deps.clock(),
      ),
    );
  }

  /// Renames [c]; blank names are ignored.
  Future<void> rename(Category c, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _write(c, name: trimmed);
  }

  /// Deletes [c] (a tombstone; memberships stay and are ignored).
  Future<void> delete(Category c) => _write(c, removed: true);

  /// Moves the category at [from] to index [to] in [ordered] and rewrites
  /// the orders that changed.
  Future<void> move(List<Category> ordered, int from, int to) async {
    final list = [...ordered];
    list.insert(to, list.removeAt(from));
    for (final (i, c) in list.indexed) {
      if (c.order != i) await _write(c, order: i);
    }
  }

  Future<void> _write(
    Category c, {
    String? name,
    int? order,
    bool removed = false,
  }) => deps.repos.categories.upsert(
    Category(
      id: c.id,
      name: name ?? c.name,
      order: order ?? c.order,
      updatedAt: nextStamp(deps.clock(), c.updatedAt),
      removed: removed,
    ),
  );
}

final _rng = Random.secure();

String _randomId() => [
  for (var i = 0; i < 16; i++)
    _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();
