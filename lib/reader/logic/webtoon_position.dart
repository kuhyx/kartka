/// Where one list item sits in the viewport, as fractions of its height
/// (0 = top edge, 1 = bottom edge), as reported by an item positions
/// listener.
typedef WebtoonItemPosition = ({int index, double leading, double trailing});

/// The item the reader is "on" in a continuous scroll, or null if none
/// is visible.
///
/// Normally that is the item under the middle of the viewport. When the
/// bottom-most visible item ends on screen the list has run out, so that
/// item wins: otherwise a short final item could never become current.
int? currentWebtoonItem(Iterable<WebtoonItemPosition> positions) {
  if (positions.isEmpty) return null;
  final sorted = positions.toList()..sort((a, b) => a.index.compareTo(b.index));
  final last = sorted.last;
  if (last.trailing <= 1) return last.index;
  for (final p in sorted) {
    if (p.leading <= 0.5 && p.trailing > 0.5) return p.index;
  }
  return sorted.first.index;
}
