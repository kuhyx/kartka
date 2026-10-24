import 'package:flutter/foundation.dart';

/// One slot of the reader's item list: a page, or a chapter transition.
@immutable
class StripSlot {
  /// The page at [index] within the chapter.
  const new page(int this.index) : _kind = 0;

  /// The transition screen leading to the previous chapter.
  const new previousChapter() : index = null, _kind = -1;

  /// The transition screen leading to the next chapter.
  const new nextChapter() : index = null, _kind = 1;

  /// Page index for page slots, null for transitions.
  final int? index;
  final int _kind;

  /// Whether this slot shows a page.
  bool get isPage => _kind == 0;

  /// Whether this is the leading (previous chapter) transition.
  bool get isPreviousChapter => _kind < 0;

  @override
  bool operator ==(Object other) =>
      other is StripSlot && other._kind == _kind && other.index == index;

  @override
  int get hashCode => Object.hash(_kind, index);

  @override
  String toString() => switch (_kind) {
    0 => 'StripSlot.page($index)',
    < 0 => 'StripSlot.previousChapter()',
    _ => 'StripSlot.nextChapter()',
  };
}

/// Maps the reader's item list (transition, pages..., transition) to slots.
///
/// The transitions are real list items so swiping past either end of the
/// chapter lands on a screen that offers the neighbouring chapter.
@immutable
class ChapterStrip {
  /// A strip for a chapter with [pageCount] pages.
  const new({required this.pageCount});

  /// Pages in the current chapter.
  final int pageCount;

  /// Items in the list: every page plus the two transitions.
  int get itemCount => pageCount + 2;

  /// The slot shown at list item [item]; out-of-range items clamp.
  StripSlot slotAt(int item) {
    if (item <= 0) return const StripSlot.previousChapter();
    if (item > pageCount) return const StripSlot.nextChapter();
    return StripSlot.page(item - 1);
  }

  /// The list item that shows [page], clamped into the chapter.
  int itemForPage(int page) {
    if (pageCount == 0) return 1;
    return page.clamp(0, pageCount - 1) + 1;
  }
}
