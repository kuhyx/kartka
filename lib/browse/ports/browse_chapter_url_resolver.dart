import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/models/models.dart';

/// Tracking's `ChapterUrlResolver` port: chapter number → chapter url.
class BrowseChapterUrlResolver {
  /// Creates the port over [store].
  BrowseChapterUrlResolver(this._store);

  final ChapterStore _store;

  /// Url of the chapter numbered [chapterNumber] in [key] (the oldest one
  /// when several releases share the number), or null when there is none or
  /// the chapters cannot be loaded.
  Future<String?> resolve(MangaKey key, int chapterNumber) async {
    final List<ChapterInfo> chapters;
    try {
      chapters = await _store.load(key);
    } on Object {
      return null;
    }
    for (final c in readingOrder(chapters)) {
      if (c.number == chapterNumber) return c.url;
    }
    return null;
  }
}
