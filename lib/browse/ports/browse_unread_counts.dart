import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/combine_latest.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/library/ports.dart';

/// Library's `UnreadCounts` port: cached chapters minus the read set.
///
/// Never fetches: a manga whose chapters were not loaded yet reads as null
/// (unknown) rather than triggering one request per library row.
class BrowseUnreadCounts implements UnreadCounts {
  /// Creates the port over `store` and `progress`.
  new(this._store, this._progress);

  final ChapterStore _store;
  final ProgressRepository _progress;

  /// Unread chapter count of [key]; null while its chapters are unknown.
  @override
  Stream<int?> watch(MangaKey key) => combineLatest2(
    _store.watch(key),
    _progress.readChapters(key),
    (chapters, read) => chapters?.where((c) => !read.contains(c.url)).length,
  );
}
