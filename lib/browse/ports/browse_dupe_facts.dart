import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/detail_store.dart';
import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/migration/dedupe/dupe_facts.dart';

/// Migration's `DupeFactsLookup` port: the stored details, the stored
/// chapter list and the chapters `isChapterRead` holds for.
///
/// Never fetches: a manga whose chapters this device never stored reads as
/// null, so duplicate merging leaves it alone.
class BrowseDupeFacts implements DupeFactsLookup {
  /// Creates the port over `store`, `details` and `progress`.
  new(this._store, this._details, this._progress);

  final ChapterStore _store;
  final DetailStore _details;
  final ProgressRepository _progress;

  @override
  Future<DupeFacts?> of(MangaKey key) async {
    final chapters = await _store.stored(key);
    if (chapters == null) return null;
    final marks = await watchReadMarks(_progress, key).first;
    return (
      details: await _details.read(key),
      chapters: chapters,
      readUrls: readUrls(chapters, marks),
    );
  }
}
