/// The §5 cut rules, score weights and freshness limit, defined once.
///
/// The evaluator applies these; the app only explains them, so a value here
/// must match `docs/DOCS-contracts.md` §5 (checked by `explain_test.dart`).
abstract final class HealthThresholds {
  /// Uptime ratio below this cuts a source, once its window is final.
  static const double minUptimeRatio = 0.95;

  /// Any challenge rate above this cuts a source (i.e. any blocking at all).
  static const double maxChallengeRate = 0;

  /// Coverage ratio below this cuts a source.
  static const double minCoverageRatio = 0.60;

  /// Overlap with a better source at or above this makes a source a subset.
  static const double subsetOverlap = 0.90;

  /// Uptime window length.
  static const int uptimeWindowDays = 7;

  /// Uptime probes per day.
  static const int probesPerDay = 4;

  /// Probes in a full window; uptime is "accruing" below this.
  static const int uptimeProbesTarget = uptimeWindowDays * probesPerDay;

  /// Results older than this get a stale warning (weekly run + one day).
  static const Duration staleAfter = Duration(days: 8);

  /// Score weight of coverage.
  static const double weightCoverage = 0.30;

  /// Score weight of chapter completeness.
  static const double weightCompleteness = 0.20;

  /// Score weight of uptime.
  static const double weightUptime = 0.20;

  /// Score weight of image quality.
  static const double weightImageQuality = 0.15;

  /// Score weight of latency.
  static const double weightLatency = 0.15;

  /// Image width that earns the full image-quality score.
  static const double fullWidthPx = 1400;

  /// p95 latency at which the latency score reaches 0.
  static const double worstP95Ms = 5000;
}
