import 'package:kartka/core/models/models.dart';

/// Told about chapters that newly appeared in a manga's stored chapter list.
///
/// Browse's `ChapterStore` calls every registered sink (looked up with
/// `registry.all<ChapterAdditionSink>()` at call time) whenever a fetch
/// replaces a stored list and adds chapters to it, whichever path fetched:
/// the detail page opening or refreshing, `ChapterUpdateChecker.check`, the
/// reader or tracking's resolver. A first fetch (nothing stored yet) is a
/// baseline and reports nothing. Owner: updates (its feed).
///
/// [record] must not throw for a bad input; the store does not await it.
abstract interface class ChapterAdditionSink {
  /// [added] (oldest first, never empty) appeared in [key]'s list.
  Future<void> record(MangaKey key, List<ChapterInfo> added);
}
