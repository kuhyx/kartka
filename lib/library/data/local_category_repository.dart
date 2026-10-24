import 'dart:convert';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/category_repository.dart';
import 'package:kartka/library/data/kv_table.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/library/data/mark.dart';
import 'package:kartka/platform/key_value_store.dart';

/// [CategoryRepository] on a [KeyValueStore].
///
/// Categories live under `categories/<sha1(id)>` (LWW on `updatedAt`);
/// membership under `membership/<mangaKeyHash>/<sha1(categoryId)>` as LWW
/// [Mark]s, so leaving a category is a tombstone that merges like a join.
class LocalCategoryRepository implements CategoryRepository {
  /// Creates the repository; [now] stamps membership changes.
  new(KeyValueStore store, {DateTime Function()? now})
    : _now = now ?? utcNow,
      _categories = KvTable(
        store,
        'categories/',
        decode: Category.fromJson,
        encode: (c) => c.toJson(),
      ),
      _members = KvTable(
        store,
        'membership/',
        decode: Mark.fromJson,
        encode: (m) => m.toJson(),
      );

  final DateTime Function() _now;
  final KvTable<Category> _categories;
  final KvTable<Mark> _members;

  @override
  Stream<List<Category>> watch() => _categories.watch().map((rows) {
    final live = rows.values.where((c) => !c.removed).toList()
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
      });
    return List.unmodifiable(live);
  });

  @override
  Future<void> upsert(Category c) => _categories.update(
    mangaKeyHash(c.id),
    (current) => current == null
        ? c
        : lwwMerge<Category>(
            current,
            c,
            at: (x) => x.updatedAt,
            tie: (x) => jsonEncode(x.toJson()),
          ),
  );

  @override
  // The positional bool is fixed by the shared interface (contracts §8).
  Future<void> setMembership(MangaKey key, String categoryId, bool member) =>
      _members.update(
        '${mangaKeyHash(key)}/${mangaKeyHash(categoryId)}',
        (current) => flip(current, key, categoryId, on: member, now: _now()),
      );

  @override
  Stream<Map<MangaKey, Set<String>>> watchMembership() =>
      _members.watch().map((rows) {
        final out = <MangaKey, Set<String>>{};
        for (final m in rows.values.where((m) => m.on)) {
          (out[m.key] ??= {}).add(m.target);
        }
        return Map.unmodifiable(out);
      });
}
