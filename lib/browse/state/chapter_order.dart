import 'package:kartka/core/models/chapter_info.dart';

/// [chapters] oldest-first. When every chapter has a number they are sorted
/// by it (stable, so same-number releases keep source order); otherwise the
/// source order is trusted and reversed, since sources list newest-first.
List<ChapterInfo> readingOrder(List<ChapterInfo> chapters) {
  if (chapters.every((c) => c.number != null)) {
    final indexed = chapters.indexed.toList()
      ..sort((a, b) {
        final byNumber = a.$2.number!.compareTo(b.$2.number!);
        return byNumber != 0 ? byNumber : a.$1.compareTo(b.$1);
      });
    return [for (final (_, c) in indexed) c];
  }
  return chapters.reversed.toList();
}

/// The chapter "Read" opens: the first unread one in [order], or the first
/// chapter when everything is read; null when there are no chapters.
ChapterInfo? firstUnread(List<ChapterInfo> order, Set<String> read) {
  for (final c in order) {
    if (!read.contains(c.url)) return c;
  }
  return order.isEmpty ? null : order.first;
}

/// Chapters of [order] whose url is not in [read], order kept.
List<ChapterInfo> unreadOf(List<ChapterInfo> order, Set<String> read) => [
  for (final c in order)
    if (!read.contains(c.url)) c,
];
