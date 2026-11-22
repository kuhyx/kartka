part of 'manga_detail_controller.dart';

/// What the detail screen shows before the network answers.
extension _Seed on MangaDetailController {
  /// Shows the library entry and stored chapters, when there is an entry;
  /// else the hovered or pressed [tile]'s title and cover, provisionally
  /// ([listPending]: fresh details replace them, a failure takes them back).
  Future<void> _seed(MangaSummary? tile) async {
    final stored = await storedDetail(_deps, key);
    if (stored == null) {
      if (tile == null || details != null) return;
      details = MangaDetails(
        sourceId: sourceId,
        url: mangaUrl,
        title: tile.title,
        coverUrl: tile.coverUrl,
      );
      listPending = true;
      _notify();
      return;
    }
    listPending = false; // Stored data shows: a failed refresh keeps it.
    details = stored.$1;
    chapters = readingOrder(stored.$2);
    _notify();
  }

  /// Shows [list] as it lands when details show but none do (2d26b6d5).
  void _early(List<ChapterInfo> list) {
    if (details == null || chapters.isNotEmpty) return;
    chapters = readingOrder(list);
    _notify();
  }
}
