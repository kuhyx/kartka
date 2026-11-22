import 'package:kartka/core/models/models.dart';

/// Chapter lists this device already fetched (DOCS-contracts §8; owner:
/// browse, from its chapter store). The reader names a chapter's
/// neighbours from it at open, before the source's fresh list arrives.
abstract interface class StoredChapterLists {
  /// The stored chapters of [key] (source order), or null when this device
  /// never fetched them. Never fetches.
  Future<List<ChapterInfo>?> stored(MangaKey key);
}
