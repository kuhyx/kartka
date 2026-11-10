/// Word-free painted values for each §5 metric (textgate). The worded
/// forms in `metric_text.dart` stay for search and screen readers.
library;

import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/thresholds.dart';

/// `96 % (27/28)`, or `9/28` while the probe window fills.
String uptimeValue(UptimeMetric? u) => u?.status == UptimeStatus.accruing
    ? '${u!.probes ?? 0}/${HealthThresholds.uptimeProbesTarget}'
    : uptimeText(u);

/// The challenge rate, `35 %`; the kinds show as reason glyphs.
String blockingValue(BlockingMetric? b) =>
    b == null ? notMeasured : pctOrDash(b.challengeRate);

/// `512/650 (79 %)`, then ` · 480` titles with their chapters when known.
String coverageValue(CoverageMetric? c) => c == null
    ? notMeasured
    : '${c.found ?? '?'}/${c.referenceSize ?? '?'} (${pctOrDash(c.ratio)})'
          '${c.complete == null ? '' : ' · ${c.complete}'}';

/// `97 % · 40`: median completeness over the sampled titles.
String completenessValue(CompletenessMetric? c) {
  if (c == null) return notMeasured;
  final over = c.sampled == null ? '' : ' · ${c.sampled}';
  return '${pctOrDash(c.medianRatio)}$over';
}

/// `92 % · 25`: pages that loaded, of the pages sampled.
String pagesLoadValue(PagesLoadMetric? p) =>
    p == null ? notMeasured : '${pctOrDash(p.ratio)} · ${p.sampled ?? '?'}';

/// The origins (`originIcon` keys) that can read the site, in §5 order;
/// null when not measured.
List<String>? availableOrigins(AvailabilityMetric? a) {
  if (a == null) return null;
  if ([a.native, a.mangayomiJs, a.keiyoushi].every((f) => f == null)) {
    return null;
  }
  return [
    if (a.native ?? false) 'native',
    if (a.mangayomiJs ?? false) 'plugin',
    if (a.keiyoushi ?? false) 'suwayomi',
  ];
}
