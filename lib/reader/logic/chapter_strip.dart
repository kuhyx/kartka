import 'package:flutter/foundation.dart';

/// One slot of the reader's item list: a page, or an edge of the strip.
@immutable
class StripSlot {
  /// Page [index] of the [segment]-th loaded chapter, [flat] among every
  /// loaded page (defaults to [index], right for the first chapter).
  const new page(int this.index, {this.segment = 0, int? flat})
    : flat = flat ?? index,
      _kind = 0;

  /// The leading edge: the previous chapter, or "No previous chapter".
  const new previousChapter()
    : index = null,
      segment = 0,
      flat = null,
      _kind = -1;

  /// The trailing edge: the next chapter loading, failed, or the end.
  const new nextChapter() : index = null, segment = 0, flat = null, _kind = 1;

  /// Page index within its chapter for page slots, null for edges.
  final int? index;

  /// Which loaded chapter a page belongs to (0 = the one opened).
  final int segment;

  /// Index among all loaded pages, null for edges.
  final int? flat;

  final int _kind;

  /// Whether this slot shows a page.
  bool get isPage => _kind == 0;

  /// Whether this is the leading (previous chapter) edge.
  bool get isPreviousChapter => _kind < 0;

  @override
  bool operator ==(Object other) =>
      other is StripSlot &&
      other._kind == _kind &&
      other.index == index &&
      other.segment == segment &&
      other.flat == flat;

  @override
  int get hashCode => Object.hash(_kind, index, segment, flat);

  @override
  String toString() => switch (_kind) {
    0 when segment == 0 => 'StripSlot.page($index)',
    0 => 'StripSlot.page($index, segment: $segment)',
    < 0 => 'StripSlot.previousChapter()',
    _ => 'StripSlot.nextChapter()',
  };
}

/// Maps the reader's item list (edge, pages of every loaded chapter, edge)
/// to slots.
///
/// Loaded chapters follow each other with no slot in between, so one swipe
/// past a chapter's last page lands on the next chapter's first. The next
/// chapter's first page takes the trailing edge's item: appending a chapter
/// never shifts an index, so the views keep their position.
@immutable
class ChapterStrip {
  /// A strip of loaded chapters with these page counts, in reading order.
  const new({required this.pageCounts});

  /// Pages in each loaded chapter.
  final List<int> pageCounts;

  /// Pages across every loaded chapter.
  int get pageCount => pageCounts.fold(0, (a, b) => a + b);

  /// Items in the list: every page plus the two edges.
  int get itemCount => pageCount + 2;

  /// Flat index of the first page of [segment].
  int offsetOf(int segment) =>
      pageCounts.take(segment).fold(0, (a, b) => a + b);

  /// The slot shown at list item [item]; out-of-range items clamp.
  StripSlot slotAt(int item) {
    if (item <= 0) return const StripSlot.previousChapter();
    var flat = item - 1;
    final whole = flat;
    for (var s = 0; s < pageCounts.length; s++) {
      if (flat < pageCounts[s]) {
        return StripSlot.page(flat, segment: s, flat: whole);
      }
      flat -= pageCounts[s];
    }
    return const StripSlot.nextChapter();
  }

  /// The list item that shows [page] of [segment], clamped into it.
  int itemForPage(int page, {int segment = 0}) {
    final count = pageCounts[segment];
    final offset = offsetOf(segment);
    if (count == 0) return offset + 1;
    return offset + page.clamp(0, count - 1) + 1;
  }
}
