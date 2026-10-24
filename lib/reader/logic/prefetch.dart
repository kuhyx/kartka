/// Page indices to fetch ahead of [current]: the next [ahead] pages that
/// exist in a chapter of [total] pages.
List<int> prefetchIndices({
  required int current,
  required int total,
  required int ahead,
}) {
  if (total <= 0) return const [];
  final from = current.clamp(0, total - 1) + 1;
  final to = (from + ahead).clamp(from, total);
  return [for (var i = from; i < to; i++) i];
}

/// Pages worth keeping in memory: the one behind [current] (for swiping
/// back), [current] itself and the prefetch window.
Set<int> retainWindow({
  required int current,
  required int total,
  required int ahead,
}) {
  if (total <= 0) return const {};
  final c = current.clamp(0, total - 1);
  return {
    if (c > 0) c - 1,
    c,
    ...prefetchIndices(current: c, total: total, ahead: ahead),
  };
}
