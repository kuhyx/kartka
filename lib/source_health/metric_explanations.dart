/// What each §5 metric means, its threshold, and how this source fares —
/// the content of the per-source detail page.
library;

import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/thresholds.dart';

/// How a source fares on one metric.
enum MetricStatus {
  /// Clears its low-score bar.
  pass,

  /// Below its bar: a reason the score is low.
  fail,

  /// Below its bar on a source kept on score anyway: a warning.
  warn,

  /// Still accruing data; no verdict yet.
  pending,

  /// Scored (or shown) but never a low-score reason.
  info,

  /// Not measured.
  unknown,
}

/// One metric, explained.
class MetricExplanation {
  /// Creates an explanation.
  const new({
    required this.title,
    required this.value,
    required this.meaning,
    required this.threshold,
    required this.status,
  });

  /// Metric name.
  final String title;

  /// This source's value, formatted.
  final String value;

  /// What is measured, in plain words.
  final String meaning;

  /// The rule applied to it (low-score bar and/or score weight).
  final String threshold;

  /// How this source fares.
  final MetricStatus status;

  /// This explanation with a [MetricStatus.warn] status.
  MetricExplanation warning() => MetricExplanation(
    title: title,
    value: value,
    meaning: meaning,
    threshold: threshold,
    status: MetricStatus.warn,
  );
}

String _weight(double w) => '${pct(w)} of the score';

/// Every metric of [r], in display order. On a source kept on score, a
/// metric below its bar only warns.
///
/// Weights are the shares of [profile] after normalisation (the DEFAULT
/// profile unless given).
List<MetricExplanation> explainMetrics(
  SourceHealthRecord r, {
  ScoringProfile profile = defaultScoringProfile,
}) {
  final kept = r.verdict == HealthVerdict.keep;
  return [
    for (final e in _explainMetrics(r, profile.weights.normalised))
      if (kept && e.status == MetricStatus.fail) e.warning() else e,
  ];
}

List<MetricExplanation> _explainMetrics(
  SourceHealthRecord r,
  ScoreWeights w,
) => [
  MetricExplanation(
    title: 'Uptime',
    value: uptimeText(r.uptime),
    meaning:
        'Share of uptime probes (${HealthThresholds.probesPerDay} a day over '
        'the last ${HealthThresholds.uptimeWindowDays} days) that got a '
        'healthy answer.',
    threshold:
        'Low-score reason below ${pct(HealthThresholds.minUptimeRatio)}, but '
        'only once all ${HealthThresholds.uptimeProbesTarget} probes are in. '
        '${_weight(w.uptime)}.',
    status: _uptime(r.uptime),
  ),
  MetricExplanation(
    title: 'Latency',
    value: latencyText(r.latency),
    meaning:
        'How long the source takes to answer: the median (p50) and the '
        'slowest 5 % (p95).',
    threshold:
        'Never a reason. ${_weight(w.speed)}: full '
        'marks at p95 0 ms, none at p95 '
        '${millis(HealthThresholds.worstP95Ms.round())} or slower.',
    status: _info(r.latency),
  ),
  MetricExplanation(
    title: 'Blocking',
    value: blockingText(r.blocking),
    meaning:
        'Share of requests answered with a Cloudflare challenge, a '
        'captcha, 403 Forbidden or 429 Too Many Requests, or by an '
        'extension that needs a browser engine.',
    threshold:
        'Low-score reason above ${pct(HealthThresholds.maxChallengeRate)}: '
        'Kartka never bypasses challenges; '
        '${pct(HealthThresholds.hardChallengeRate)} or more rules the source '
        'out whatever its score. Needing a browser engine only raises the '
        '"Needs browser engine" flag.',
    status: (r.blocking?.onlyBrowserEngine ?? false)
        ? MetricStatus.info
        : _below(r.blocking?.challengeRate, HealthThresholds.maxChallengeRate),
  ),
  MetricExplanation(
    title: 'Coverage',
    value: coverageText(r.coverage),
    meaning:
        'How many reference titles (your library backup plus the AniList '
        'top 500) the source has. The score counts a title only with at '
        'least ${pct(HealthThresholds.completeChapterRatio)} of its '
        'chapters.',
    threshold:
        'Low-score reason below ${pct(HealthThresholds.minCoverageRatio)} '
        'found. ${_weight(w.completeCoverage)}.',
    status: _atLeast(r.coverage?.ratio, HealthThresholds.minCoverageRatio),
  ),
  MetricExplanation(
    title: 'Chapter completeness',
    value: completenessText(r.completeness),
    meaning:
        "Chapters on the source compared with AniList's chapter count, "
        'median over sampled titles, capped at 100 %.',
    threshold: 'Never a reason. Scored as part of Coverage.',
    status: _info(r.completeness),
  ),
  MetricExplanation(
    title: 'Image quality',
    value: r.imageQuality == null
        ? notMeasured
        : '${imageWidthText(r.imageQuality)} wide, JPEG '
              '${jpegQualityText(r.imageQuality)}',
    meaning:
        'Median page width and estimated JPEG quality over sampled '
        'pages. Wider and higher-quality pages read better.',
    threshold:
        'Never a reason. ${_weight(w.imageQuality)}: full '
        'marks at ${HealthThresholds.fullWidthPx.round()} px wide or more.',
    status: _info(r.imageQuality),
  ),
  MetricExplanation(
    title: 'Subset of another source',
    value: r.subsetOf == null
        ? (r.coverage == null ? notMeasured : 'no')
        : '${pctOrDash(r.subsetOf!.overlap)} overlap with '
              '${r.subsetOf!.sourceId}',
    meaning:
        'Whether a higher-ranked source with images at least as good '
        'already has most of these titles.',
    threshold:
        'From ${pct(HealthThresholds.subsetOverlap)} of its titles on such '
        'a source, the score is multiplied by 1 − '
        '${HealthThresholds.subsetPenalty} × that share.',
    status: r.subsetOf != null
        ? MetricStatus.fail
        : (r.coverage == null ? MetricStatus.unknown : MetricStatus.pass),
  ),
  MetricExplanation(
    title: 'Available as',
    value: availabilityText(r.availability),
    meaning:
        'Which ways of reading this site exist: a native Kartka source, '
        'a converted Mangayomi JS plugin, or a Keiyoushi extension through '
        'Suwayomi.',
    threshold: 'Informational; not scored.',
    status: _info(r.availability),
  ),
  if (r.pagesLoad != null)
    MetricExplanation(
      title: 'Pages load',
      value: pagesLoadText(r.pagesLoad),
      meaning:
          'Share of sampled chapter pages whose images actually downloaded.',
      threshold: 'Multiplies the weighted score (see the score breakdown).',
      status: MetricStatus.info,
    ),
];

MetricStatus _info(Object? block) =>
    block == null ? MetricStatus.unknown : MetricStatus.info;

MetricStatus _uptime(UptimeMetric? u) {
  if (u == null) return MetricStatus.unknown;
  if (u.status == UptimeStatus.accruing) return MetricStatus.pending;
  return _atLeast(u.ratio, HealthThresholds.minUptimeRatio);
}

MetricStatus _atLeast(double? v, double min) {
  if (v == null) return MetricStatus.unknown;
  return v < min ? MetricStatus.fail : MetricStatus.pass;
}

MetricStatus _below(double? v, double max) {
  if (v == null) return MetricStatus.unknown;
  return v > max ? MetricStatus.fail : MetricStatus.pass;
}
