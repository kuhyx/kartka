/// The §5 low-score reasons, keep bar, score weights and freshness limit,
/// defined once.
///
/// The evaluator applies these; the app only explains them, so a value here
/// must match `docs/DOCS-contracts.md` §5 (checked by `explain_test.dart`).
abstract final class HealthThresholds {
  /// Uptime ratio below this is a low-score reason, once its window is final.
  static const double minUptimeRatio = 0.95;

  /// Any challenge rate above this is a low-score reason (any blocking at
  /// all), except `webview`, which is flagged instead.
  static const double maxChallengeRate = 0;

  /// Coverage ratio below this is a low-score reason.
  static const double minCoverageRatio = 0.60;

  /// Overlap with a better source at or above this makes a source a subset.
  static const double subsetOverlap = 0.90;

  /// The score is the only judgement: at or above this a source is kept,
  /// below it cut (pending only while unmeasured). A kept source's reasons
  /// are shown as warnings.
  static const double keepScore = 0.90;

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
