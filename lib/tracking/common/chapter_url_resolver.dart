import 'package:kartka/core/models/manga_key.dart';

/// Maps between chapter numbers and local chapter URLs (contracts §13).
///
/// Port declared by tracking, supplied by browse (from its chapter cache)
/// through `KartkaFeature.services`. Both directions are best-effort: `null`
/// means unknown, and tracking then skips that pull or that read mark, so no
/// synthetic chapter URL ever reaches the synced `progress/` path.
abstract interface class ChapterUrlResolver {
  /// The URL of chapter [chapterNumber] of [key], or `null` when unknown.
  Future<String?> resolve(MangaKey key, int chapterNumber);

  /// The chapter number of [chapterUrl] in [key], or `null` when unknown.
  Future<double?> numberOf(MangaKey key, String chapterUrl);
}
