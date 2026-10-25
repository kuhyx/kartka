/// The §5 low-score reasons, score scales and freshness limit, defined once.
///
/// The evaluator applies these; the app only explains them, so a value here
/// must match `docs/DOCS-contracts-source-health.md` §5 (checked by
/// `explain_test.dart` and the shared scoring fixture). The score weights and
/// the keep bar are the active scoring profile's, with the DEFAULT in
/// `scoring/profile.dart`.
abstract final class HealthThresholds {
  /// Uptime ratio below this is a low-score reason, once its window is final.
  static const double minUptimeRatio = 0.95;

  /// Any challenge rate above this is a low-score reason (any blocking at
  /// all), except `webview`, which is flagged instead.
  static const double maxChallengeRate = 0;

  /// Coverage ratio below this is a low-score reason.
  static const double minCoverageRatio = 0.60;

  /// Overlap with a better source at or above this makes a source a subset,
  /// which multiplies its score by 1 − [subsetPenalty] × overlap.
  static const double subsetOverlap = 0.50;

  /// See [subsetOverlap].
  static const double subsetPenalty = 0.5;

  /// A non-webview challenge rate at or above this cuts (`blocking>=0.50`).
  static const double hardChallengeRate = 0.5;

  /// Share of the reference chapter count a found title needs to count for
  /// the merged coverage.
  static const double completeChapterRatio = 0.8;

  /// Runs before the merged coverage: its part is this share of the old
  /// coverage ratio plus the rest of the chapter completeness.
  static const double legacyCoverageShare = 0.6;

  /// Uptime window length.
  static const int uptimeWindowDays = 7;

  /// Uptime probes per day.
  static const int probesPerDay = 4;

  /// Probes in a full window; uptime is "accruing" below this.
  static const int uptimeProbesTarget = uptimeWindowDays * probesPerDay;

  /// Results older than this get a stale warning (weekly run + one day).
  static const Duration staleAfter = Duration(days: 8);

  /// Image width that earns the full image-quality score.
  static const double fullWidthPx = 1067;

  /// p95 latency at which the latency score reaches 0.
  static const double worstP95Ms = 5000;
}
