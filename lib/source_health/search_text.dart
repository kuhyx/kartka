/// Everything a record holds, as the text the search box matches against.
library;

import 'package:kartka/source_health/cut_reasons.dart';
import 'package:kartka/source_health/labels.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/reason_filter.dart';

/// The searchable text of [r]: `primary` (name and id) weighs more than
/// `secondary` (origin, language, verdict, reasons in codes and in words,
/// blocking kinds, availability, subset target, flags and every rendered
/// metric). [nameOf] names the subset target.
({List<String> primary, List<String> secondary}) searchTextOf(
  SourceHealthRecord r, {
  SourceNameOf? nameOf,
}) {
  final subset = r.subsetOf;
  final scope = r.langScope;
  final pages = r.pagesLoad;
  return (
    primary: [r.name, r.id],
    secondary: [
      r.origin,
      originLabel(r.origin),
      r.lang,
      if (scope != null) ...[scope, langScopeLabel(scope)],
      r.verdict.name,
      verdictLabel(r.verdict),
      ...r.cutReasons,
      ...explainCutReasons(r, nameOf: nameOf),
      for (final reason in reasonsOf(r)) reason.label,
      for (final kind in r.blocking?.kinds ?? const <String>[]) ...[
        kind,
        describeBlockingKind(kind),
      ],
      availabilityText(r.availability),
      if (subset != null) ...[subset.sourceId, ?nameOf?.call(subset.sourceId)],
      ...r.flags,
      uptimeText(r.uptime),
      latencyText(r.latency),
      blockingText(r.blocking),
      coverageText(r.coverage),
      completenessText(r.completeness),
      imageWidthText(r.imageQuality),
      jpegQualityText(r.imageQuality),
      scoreText(r.score),
      if (pages != null) pagesLoadText(pages),
    ],
  );
}
