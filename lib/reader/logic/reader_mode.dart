import 'package:flutter/material.dart';

/// How the reader lays out the pages of a chapter.
enum ReaderMode {
  /// One page at a time, swiping left to advance.
  pagedLtr('paged_ltr', 'Paged (left to right)'),

  /// One page at a time, swiping right to advance (manga order).
  pagedRtl('paged_rtl', 'Paged (right to left)'),

  /// One page at a time, swiping up to advance.
  verticalPaged('vertical', 'Vertical paged'),

  /// Pages stacked in one continuous vertical scroll.
  webtoon('webtoon', 'Webtoon (continuous)');

  new(this.id, this.label);

  /// Stable id used for persistence.
  final String id;

  /// Human-readable name, spoken (never painted) in the mode picker.
  final String label;

  /// The glyph painted for the mode in pickers.
  IconData get icon => switch (this) {
    // Swipe glyphs, not arrows: an arrow beside the Back button reads as
    // navigation.
    pagedLtr => Icons.swipe_left,
    pagedRtl => Icons.swipe_right,
    verticalPaged => Icons.swipe_up,
    webtoon => Icons.swipe_vertical,
  };

  /// The mode stored under [id], or null when unknown or missing.
  static ReaderMode? fromId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The scroll axis of the page list.
  Axis get axis => switch (this) {
    pagedLtr || pagedRtl => Axis.horizontal,
    verticalPaged || webtoon => Axis.vertical,
  };

  /// Whether advancing moves towards the screen's left edge.
  bool get reversed => this == pagedRtl;

  /// Whether the mode snaps to whole pages.
  bool get isPaged => this != webtoon;
}
