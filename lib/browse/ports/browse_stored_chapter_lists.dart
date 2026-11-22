import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';

/// The reader's [StoredChapterLists] port, over browse's [ChapterStore]:
/// the list this device stored, never a fetch.
class BrowseStoredChapterLists implements StoredChapterLists {
  /// Creates the port; [_store] is read on first use (the store is built
  /// lazily, after every feature factory ran).
  const new(this._store);

  final ChapterStore Function() _store;

  @override
  Future<List<ChapterInfo>?> stored(MangaKey key) => _store().stored(key);
}
