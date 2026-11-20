import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/library/ports.dart';

/// Library's `ShelfFactsLookup` port: the newest `uploadedAt` among the
/// stored chapters, and whether `isChapterRead` holds for all of them.
///
/// Never fetches: a manga whose chapters this device never stored reads as
/// null, so auto-shelving leaves it alone.
class BrowseShelfFacts implements ShelfFactsLookup {
  /// Creates the port over `store` and `progress`.
  new(this._store, this._progress);

  final ChapterStore _store;
  final ProgressRepository _progress;

  @override
  Future<ShelfFacts?> of(MangaKey key) async {
    final chapters = await _store.stored(key);
    if (chapters == null) return null;
    DateTime? newest;
    for (final c in chapters) {
      final at = c.uploadedAt;
      if (at != null && (newest == null || at.isAfter(newest))) newest = at;
    }
    final marks = await watchReadMarks(_progress, key).first;
    return (newestUpload: newest, allRead: unreadCount(chapters, marks) == 0);
  }
}
