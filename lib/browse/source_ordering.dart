import 'package:flutter/foundation.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/models/source_ref.dart';

/// Sources of one [SourceOrigin], already in display order.
@immutable
class SourceGroup {
  /// Creates a group.
  const new(this.origin, this.sources);

  /// The origin shared by every source in the group.
  final SourceOrigin origin;

  /// Sources in display order.
  final List<SourceRef> sources;
}

/// [sources] in display order: ranked sources by ascending rank, then
/// unranked ones; ties broken by case-insensitive name, then id, so the
/// order is total and stable across rebuilds.
List<SourceRef> orderSources(
  Iterable<SourceRef> sources,
  Map<String, SourceHealthSummary> health,
) {
  int compare(SourceRef a, SourceRef b) {
    final ra = health[a.id]?.rank;
    final rb = health[b.id]?.rank;
    if (ra != rb) {
      if (ra == null) return 1;
      if (rb == null) return -1;
      return ra.compareTo(rb);
    }
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  }

  return sources.toList()..sort(compare);
}

/// Groups [sources] by origin (in [SourceOrigin] declaration order, empty
/// groups omitted), each group in [orderSources] order.
List<SourceGroup> groupSources(
  Iterable<SourceRef> sources,
  Map<String, SourceHealthSummary> health,
) => [
  for (final origin in SourceOrigin.values)
    if (orderSources(sources.where((s) => s.origin == origin), health)
        case final group when group.isNotEmpty)
      SourceGroup(origin, group),
];
