import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/health_icons.dart';
import 'package:kartka/source_health/ui/skipped_page.dart';

/// `585 tested of 590 candidates · 120 keep · 400 cut · 65 pending · showing
/// 12`. Totals come from [meta] when the evaluator published it; otherwise
/// (or per missing field) they are counted from [records], and the
/// candidate total is unknown.
String countsLine(
  List<SourceHealthRecord> records,
  SourceHealthMeta? meta,
  int showing,
) {
  final v = _verdicts(records, meta);
  final tested = meta?.tested ?? records.length;
  final candidates = meta?.candidates;
  final of = candidates == null
      ? '$tested tested · candidates unknown'
      : '$tested tested of $candidates candidates';
  return '$of · ${v.keep} keep · ${v.cut} cut · ${v.pending} pending · '
      'showing $showing';
}

/// Verdict totals from [meta], else counted from [records].
VerdictCounts _verdicts(
  List<SourceHealthRecord> records,
  SourceHealthMeta? meta,
) {
  int count(HealthVerdict v) => records.where((r) => r.verdict == v).length;
  return meta?.verdicts ??
      VerdictCounts(
        keep: count(HealthVerdict.keep),
        cut: count(HealthVerdict.cut),
        pending: count(HealthVerdict.pending),
      );
}

/// The counts over the ranking as glyphs and numbers (spoken as
/// [countsLine]). With a run summary it opens the
/// [SkippedPage]; without one it is plain text.
class CountsHeader extends StatelessWidget {
  /// Creates the header.
  const new({
    required this.records,
    required this.meta,
    required this.showing,
    super.key,
  });

  /// Every record of the ranking.
  final List<SourceHealthRecord> records;

  /// The run summary, or null when the evaluator has not published one.
  final SourceHealthMeta? meta;

  /// Records left after search and filters.
  final int showing;

  @override
  Widget build(BuildContext context) {
    final v = _verdicts(records, meta);
    final tested = meta?.tested ?? records.length;
    final candidates = meta?.candidates;
    Widget mark(IconData icon, Object n, [Color? color]) =>
        IconValue(icon, '$n', semanticLabel: '', color: color);
    final line = SpokenLabel(
      key: const Key('counts'),
      semanticLabel: countsLine(records, meta, showing),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: AppSpacing.md,
          children: [
            mark(
              Icons.science_outlined,
              candidates == null ? tested : '$tested/$candidates',
            ),
            for (final (verdict, n) in [
              (HealthVerdict.keep, v.keep),
              (HealthVerdict.cut, v.cut),
              (HealthVerdict.pending, v.pending),
            ])
              mark(verdictIcon(verdict), n, verdictFill(context, verdict)),
            mark(Icons.visibility_outlined, showing),
          ],
        ),
      ),
    );
    final m = meta;
    if (m == null) return line;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => SkippedPage(meta: m))),
      child: Row(
        spacing: AppSpacing.xs,
        children: [
          Expanded(child: line),
          const Icon(Icons.chevron_right, semanticLabel: 'Skipped candidates'),
        ],
      ),
    );
  }
}
