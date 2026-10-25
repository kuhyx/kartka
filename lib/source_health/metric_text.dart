/// One-line display values for each §5 metric, shared by the ranking list
/// and the detail page.
library;

import 'package:kartka/source_health/cut_reasons.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/thresholds.dart';

/// `96 % (27/28)`, or `accruing 9/28 probes` while the window fills.
String uptimeText(UptimeMetric? u) {
  if (u == null) return notMeasured;
  if (u.status == UptimeStatus.accruing) {
    return 'accruing ${u.probes ?? 0}/${HealthThresholds.uptimeProbesTarget} '
        'probes';
  }
  return '${pctOrDash(u.ratio)} (${u.ok ?? '?'}/${u.probes ?? '?'})';
}

/// `p50 420 ms · p95 1.3 s`.
String latencyText(LatencyMetric? l) =>
    l == null ? notMeasured : 'p50 ${millis(l.p50)} · p95 ${millis(l.p95)}';

/// `none`, or `35 % (Cloudflare challenge, 429 Too Many Requests)`.
String blockingText(BlockingMetric? b) {
  if (b == null) return notMeasured;
  final rate = b.challengeRate;
  if ((rate ?? 0) <= HealthThresholds.maxChallengeRate && b.kinds.isEmpty) {
    return rate == null ? notMeasured : 'none';
  }
  final kinds = b.kinds.isEmpty
      ? ''
      : ' (${b.kinds.map(describeBlockingKind).join(', ')})';
  return '${pctOrDash(rate)}$kinds';
}

/// `512/650 (79 %)`: reference titles found / reference size.
String coverageText(CoverageMetric? c) => c == null
    ? notMeasured
    : '${c.found ?? '?'}/${c.referenceSize ?? '?'} (${pctOrDash(c.ratio)})';

/// `97 % over 40 titles`.
String completenessText(CompletenessMetric? c) {
  if (c == null) return notMeasured;
  final over = c.sampled == null ? '' : ' over ${c.sampled} titles';
  return '${pctOrDash(c.medianRatio)}$over';
}

/// `1100 px`.
String imageWidthText(ImageQualityMetric? q) =>
    withUnit(q?.medianWidthPx, ' px');

/// `q88`.
String jpegQualityText(ImageQualityMetric? q) {
  final v = q?.medianJpegQuality;
  return v == null ? notMeasured : 'q$v';
}

/// `0.81`.
String scoreText(double? score) =>
    score == null ? notMeasured : score.toStringAsFixed(2);

/// `native · JS plugin · Suwayomi`: the implementations that exist; `none`
/// when every reported flag is false.
String availabilityText(AvailabilityMetric? a) {
  if (a == null) return notMeasured;
  final flags = [a.native, a.mangayomiJs, a.keiyoushi];
  if (flags.every((f) => f == null)) return notMeasured;
  final names = [
    if (a.native ?? false) 'native',
    if (a.mangayomiJs ?? false) 'JS plugin',
    if (a.keiyoushi ?? false) 'Suwayomi',
  ];
  return names.isEmpty ? 'none' : names.join(' · ');
}

/// `92 % of 25 sampled`: pages that loaded / pages sampled; `— of 25
/// sampled` when the ratio could not be measured.
String pagesLoadText(PagesLoadMetric? p) {
  if (p == null) return notMeasured;
  return '${pctOrDash(p.ratio)} of ${p.sampled ?? '?'} sampled';
}
