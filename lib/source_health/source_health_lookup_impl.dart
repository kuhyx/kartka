import 'package:flutter/widgets.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/ui/health_badge.dart';

/// Browse's [SourceHealthLookup] port, backed by a [SourceHealthFeed].
class FeedSourceHealthLookup implements SourceHealthLookup {
  /// Creates a lookup over [feed].
  new(this.feed);

  /// Where the records come from.
  final SourceHealthFeed feed;

  /// Browse must render without health data, so read errors are dropped
  /// here (the Sources tab is where they are shown).
  @override
  Stream<Map<String, SourceHealthSummary>> watch() => feed
      .watch()
      .map(
        (records) => {
          for (final r in records)
            r.id: SourceHealthSummary(verdict: r.verdict, rank: r.rank),
        },
      )
      .handleError((Object _) {});

  @override
  Widget? buildBadge(
    BuildContext context,
    String sourceId,
    SourceHealthSummary? summary,
  ) => summary == null
      ? null
      : HealthBadge(verdict: summary.verdict, rank: summary.rank);
}
