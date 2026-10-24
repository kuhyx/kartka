import 'package:kartka/core/models/manga_key.dart';

/// Maps a remote chapter count back to a local chapter (contracts §13).
///
/// Port declared by tracking, supplied by browse (from its chapter cache)
/// through `KartkaFeature.services`. Tracking pulls remote progress forward
/// only when this resolves; `null` skips the pull, so no synthetic chapter
/// URL ever reaches the synced `progress/` path.
abstract interface class ChapterUrlResolver {
  /// The URL of chapter [chapterNumber] of [key], or `null` when unknown.
  Future<String?> resolve(MangaKey key, int chapterNumber);
}
