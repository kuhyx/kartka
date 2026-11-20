import 'package:kartka/core/models/manga_key.dart';

/// Fetches a chapter's page list and first images ahead, so the reader
/// opens it without waiting (971debc8). The reader registers one as a
/// service; screens that lead into the reader without the details screen
/// (the Updates sheet) ask it when the user is about to pick a chapter.
abstract interface class ChapterWarmer {
  /// Starts warming [chapterUrl] of [key] in the background; never throws.
  void warmChapter(MangaKey key, String chapterUrl);
}
