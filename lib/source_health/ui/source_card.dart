import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/cut_reasons.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/install/source_action_button.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/quality_metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/metric_strip.dart';
import 'package:kartka/source_health/ui/reason_marks.dart';
import 'package:kartka/source_health/ui/source_line_mark.dart';

/// Opens the detail page of the source with this id.
typedef OpenSource = void Function(String sourceId);

/// One row of the ranking: rank, name, verdict, score, every metric and the
/// cut reasons in plain words. Activating it opens the detail page.
class SourceCard extends StatelessWidget {
  /// Creates a card for [record].
  new({
    required this.record,
    required this.onOpen,
    required this.nameOf,
    this.keepScore = kDefaultKeepScore,
    this.installs,
  }) : super(key: ValueKey('source-${record.id}'));

  /// Install / Open state; null shows no action button.
  final SourceInstalls? installs;

  /// The active profile's keep bar, for the "kept despite" heading.
  final double keepScore;

  /// The source.
  final SourceHealthRecord record;

  /// Opens a source's detail page ([record]'s, or its subset-of target).
  final OpenSource onOpen;

  /// Names other sources (for the subset link).
  final SourceNameOf nameOf;

  @override
  Widget build(BuildContext context) {
    final r = record;
    // The action sits outside the InkWell: a disabled (installing) button
    // must not let the tap through to "open the detail page".
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _body(context, r),
          if (installs case final i?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: SourceActionButton(record: r, installs: i),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, SourceHealthRecord r) {
    final theme = Theme.of(context);
    final subset = r.subsetOf;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => onOpen(r.id),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.sm,
          children: [
            Row(
              spacing: AppSpacing.sm,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: theme.textTheme.titleMedium),
                      SourceLineMark(r),
                    ],
                  ),
                ),
                DefaultScoreMark(r),
                Text(scoreText(r.score), style: theme.textTheme.titleMedium),
                HealthBadge(verdict: r.verdict, rank: r.rank),
              ],
            ),
            if (r.needsBrowserEngine) const BrowserEngineChip(),
            if (r.reprobedOnly) const ReprobeChip(),
            MetricStrip(r),
            if (subset != null) _subsetLink(subset),
            ReasonMarks(r, nameOf: nameOf, keepScore: keepScore),
          ],
        ),
      ),
    );
  }

  /// The covering source's name and the overlap; disabled when the
  /// covering source is not in the ranking.
  Widget _subsetLink(SubsetOfMetric subset) {
    final name = nameOf(subset.sourceId) ?? subset.sourceId;
    final overlap = pctOrDash(subset.overlap);
    return TextButton.icon(
      icon: const Icon(Icons.call_split),
      onPressed: nameOf(subset.sourceId) == null
          ? null
          : () => onOpen(subset.sourceId),
      label: Text(
        '$name ($overlap)',
        semanticsLabel: 'Subset of $name ($overlap)',
      ),
    );
  }
}
