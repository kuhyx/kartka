import 'package:kartka/core/models/models.dart';

/// The user's library (DOCS-contracts §8).
abstract interface class LibraryRepository {
  /// Current entries, re-emitted on every change; removed entries excluded.
  Stream<List<LibraryEntry>> watch();

  /// Inserts or updates [e]; last-writer-wins on `updatedAt`.
  Future<void> upsert(LibraryEntry e);

  /// Tombstones the entry for [key].
  Future<void> remove(MangaKey key);
}
