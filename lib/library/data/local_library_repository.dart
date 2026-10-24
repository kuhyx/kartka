import 'dart:convert';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/library_repository.dart';
import 'package:kartka/library/data/kv_table.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/platform/key_value_store.dart';

/// [LibraryRepository] on a [KeyValueStore]: one row per entry under
/// `library/<mangaKeyHash>`, last-writer-wins on `updatedAt`.
class LocalLibraryRepository implements LibraryRepository {
  /// Creates the repository; [now] is the clock for tombstones.
  new(KeyValueStore store, {DateTime Function()? now})
    : _now = now ?? utcNow,
      _rows = KvTable(
        store,
        'library/',
        decode: LibraryEntry.fromJson,
        encode: (e) => e.toJson(),
      );

  final DateTime Function() _now;
  final KvTable<LibraryEntry> _rows;

  @override
  Stream<List<LibraryEntry>> watch() => _rows.watch().map(
    (rows) => List.unmodifiable(rows.values.where((e) => !e.removed)),
  );

  @override
  Future<void> upsert(LibraryEntry e) => _rows.update(
    mangaKeyHash(e.key),
    (current) => current == null
        ? e
        : lwwMerge<LibraryEntry>(current, e, at: _at, tie: _tie),
  );

  @override
  Future<void> remove(MangaKey key) => _rows.update(
    mangaKeyHash(key),
    (current) => current == null || current.removed
        ? null
        : current.copyWith(
            removed: true,
            updatedAt: nextStamp(_now(), current.updatedAt),
          ),
  );

  static DateTime _at(LibraryEntry e) => e.updatedAt;
  static String _tie(LibraryEntry e) => jsonEncode(e.toJson());
}
