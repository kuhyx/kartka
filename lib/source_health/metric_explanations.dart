/// What each §5 metric means, its threshold, and how this source fares —
/// the content of the per-source detail page.
library;

import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/thresholds.dart';

/// How a source fares on one metric.
enum MetricStatus {
  /// Clears the cut rule.
  pass,

  /// Triggers a cut rule.
  fail,

  /// Still accruing data; no verdict yet.
  pending,

  /// Scored but never cuts on its own.
  info,

  /// Not measured.
  unknown,
}

/// One metric, explained.
class MetricExplanation {
  /// Creates an explanation.
  const MetricExplanation({
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

  /// The rule applied to it (cut threshold and/or score weight).
  final String threshold;

  /// How this source fares.
  final MetricStatus status;
}

String _weight(double w) => '${pct(w)} of the score';

/// Every metric of [r], in display order.
List<MetricExplanation> explainMetrics(SourceHealthRecord r) => [
  MetricExplanation(
    title: 'Uptime',
    value: uptimeText(r.uptime),
    meaning:
        'Share of uptime probes (${HealthThresholds.probesPerDay} a day over '
        'the last ${HealthThresholds.uptimeWindowDays} days) that got a '
        'healthy answer.',
    threshold:
        'Cut below ${pct(HealthThresholds.minUptimeRatio)}, but only once all '
        '${HealthThresholds.uptimeProbesTarget} probes are in; until then the '
        'verdict is pending. ${_weight(HealthThresholds.weightUptime)}.',
    status: _uptime(r.uptime),
  ),
  MetricExplanation(
    title: 'Latency',
    value: latencyText(r.latency),
    meaning: 'How long the source takes to answer: the median (p50) and the '
        'slowest 5 % (p95).',
    threshold:
        'Never cuts. ${_weight(HealthThresholds.weightLatency)}: full marks '
        'at p95 0 ms, none at p95 '
        '${millis(HealthThresholds.worstP95Ms.round())} or slower.',
    status: _info(r.latency),
  ),
  MetricExplanation(
    title: 'Blocking',
    value: blockingText(r.blocking),
    meaning: 'Share of requests answered with a Cloudflare challenge, a '
        'captcha, 403 Forbidden or 429 Too Many Requests.',
    threshold:
        'Cut above ${pct(HealthThresholds.maxChallengeRate)}: Kartka never '
        'bypasses challenges, so any blocking cuts the source.',
    status: _below(r.blocking?.challengeRate, HealthThresholds.maxChallengeRate),
  ),
  MetricExplanation(
    title: 'Coverage',
    value: coverageText(r.coverage),
    meaning: 'How many reference titles (your library backup plus the AniList '
        'top 500) the source has.',
    threshold:
        'Cut below ${pct(HealthThresholds.minCoverageRatio)}. '
        '${_weight(HealthThresholds.weightCoverage)}.',
    status: _atLeast(r.coverage?.ratio, HealthThresholds.minCoverageRatio),
  ),
  MetricExplanation(
    title: 'Chapter completeness',
    value: completenessText(r.completeness),
    meaning: "Chapters on the source compared with AniList's chapter count, "
        'median over sampled titles, capped at 100 %.',
    threshold:
        'Never cuts. ${_weight(HealthThresholds.weightCompleteness)}.',
    status: _info(r.completeness),
  ),
  MetricExplanation(
    title: 'Image quality',
    value: r.imageQuality == null
        ? notMeasured
        : '${imageWidthText(r.imageQuality)} wide, JPEG '
              '${jpegQualityText(r.imageQuality)}',
    meaning: 'Median page width and estimated JPEG quality over sampled '
        'pages. Wider and higher-quality pages read better.',
    threshold:
        'Never cuts. ${_weight(HealthThresholds.weightImageQuality)}: full '
        'marks at ${HealthThresholds.fullWidthPx.round()} px wide or more.',
    status: _info(r.imageQuality),
  ),
  MetricExplanation(
    title: 'Subset of another source',
    value: r.subsetOf == null
        ? (r.coverage == null ? notMeasured : 'no')
        : '${pctOrDash(r.subsetOf!.overlap)} overlap with '
              '${r.subsetOf!.sourceId}',
    meaning: 'Whether a higher-ranked source with images at least as good '
        'already has almost all of these titles.',
    threshold:
        'Cut when ${pct(HealthThresholds.subsetOverlap)} or more of its titles '
        'are on such a source.',
    status: r.subsetOf != null
        ? MetricStatus.fail
        : (r.coverage == null ? MetricStatus.unknown : MetricStatus.pass),
  ),
  MetricExplanation(
    title: 'Available as',
    value: availabilityText(r.availability),
    meaning: 'Which ways of reading this site exist: a native Kartka source, '
        'a converted Mangayomi JS plugin, or a Keiyoushi extension through '
        'Suwayomi.',
    threshold: 'Informational; never cuts and is not scored.',
    status: _info(r.availability),
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
