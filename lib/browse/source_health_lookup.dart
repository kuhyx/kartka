import 'package:flutter/widgets.dart';

/// Evaluator verdict for a source (contracts §5 `verdict`).
enum HealthVerdict {
  /// The source passed every cut rule.
  keep,

  /// At least one cut rule fired (see the source_health screen for reasons).
  cut,

  /// Uptime is still accruing; no final verdict yet.
  pending;

  /// Parses the §5 wire value; unknown or missing values read as [pending].
  static HealthVerdict parse(String? raw) => switch (raw) {
    'keep' => keep,
    'cut' => cut,
    _ => pending,
  };
}

/// The slice of a §5 source-health record the Browse tab needs.
@immutable
class SourceHealthSummary {
  /// Creates a summary; [rank] is 1-based, null when the source is unranked.
  const new({
    required this.verdict,
    this.rank,
    this.needsBrowserEngine = false,
  });

  /// 1-based rank from the evaluator; lower is better. Null = unranked.
  final int? rank;

  /// Evaluator verdict.
  final HealthVerdict verdict;

  /// §5 flag `needs-browser-engine`: warn, but the source is not cut for it.
  final bool needsBrowserEngine;

  @override
  bool operator ==(Object other) =>
      other is SourceHealthSummary &&
      other.rank == rank &&
      other.verdict == verdict &&
      other.needsBrowserEngine == needsBrowserEngine;

  @override
  int get hashCode => Object.hash(rank, verdict, needsBrowserEngine);

  @override
  String toString() =>
      'SourceHealthSummary(rank: $rank, verdict: $verdict, '
      'needsBrowserEngine: $needsBrowserEngine)';
}

/// Optional port the source_health part implements and registers.
///
/// Browse works without it (sources are then sorted by name and show no
/// badge), so nothing here may be required for the tab to render.
abstract interface class SourceHealthLookup {
  /// Latest summaries keyed by source id (`SourceRef.id`). Emits again on
  /// every evaluator update; a source missing from the map is unranked.
  Stream<Map<String, SourceHealthSummary>> watch();

  /// The badge shown next to [sourceId] in the source list, or null for none.
  /// [summary] is null when the evaluator has no record for the source.
  Widget? buildBadge(
    BuildContext context,
    String sourceId,
    SourceHealthSummary? summary,
  );
}
