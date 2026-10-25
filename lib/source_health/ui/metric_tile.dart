import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/metric_explanations.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/score_breakdown.dart';
import 'package:kartka/source_health/thresholds.dart';
import 'package:kartka/source_health/ui/health_badge.dart';

/// The status word and fill of a [MetricStatus]; neutral states are unfilled.
(String, Color?) metricStatusStyle(BuildContext context, MetricStatus s) {
  final c = statusColors(context);
  return switch (s) {
    MetricStatus.pass => ('Passes', c.success),
    MetricStatus.fail => ('Lowers score', c.danger),
    MetricStatus.warn => ('Warns', c.warning),
    MetricStatus.pending => ('Accruing', c.warning),
    MetricStatus.info => ('Info', null),
    MetricStatus.unknown => ('Not measured', null),
  };
}

/// One metric on the detail page: value, status, meaning and threshold.
class MetricTile extends StatelessWidget {
  /// Creates a tile for [explanation].
  const new(this.explanation, {super.key});

  /// What to show.
  final MetricExplanation explanation;

  @override
  Widget build(BuildContext context) {
    final e = explanation;
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final (word, fill) = metricStatusStyle(context, e.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.xs,
        children: [
          Row(
            spacing: AppSpacing.sm,
            children: [
              Expanded(
                child: Text(e.title, style: theme.textTheme.titleMedium),
              ),
              StatusPill(text: word, fill: fill),
            ],
          ),
          Text(e.value),
          Text(e.meaning, style: muted),
          Text(e.threshold, style: muted),
        ],
      ),
    );
  }
}

/// The §5 score split into weighted parts and the pages-load multiplier,
/// recomputed from the metrics.
class ScoreTable extends StatelessWidget {
  /// Creates a table of [parts], times [pagesLoad] when the run has it.
  const new(this.parts, {this.pagesLoad, super.key});

  /// The weighted parts.
  final List<ScorePart> parts;

  /// The multiplier; null on runs before `pagesLoad`.
  final PagesLoadMetric? pagesLoad;

  @override
  Widget build(BuildContext context) {
    final sum = parts.fold<double>(0, (s, p) => s + (p.points ?? 0));
    final ratio = pagesLoad?.ratio;
    final recomputed = switch ((pagesLoad, ratio)) {
      (null, _) => sum.toStringAsFixed(2),
      (_, null) =>
        '${sum.toStringAsFixed(2)} (pages load not measured, not applied)',
      (_, final x?) =>
        '${sum.toStringAsFixed(2)} × ${pct(x)} = '
            '${(sum * x).toStringAsFixed(2)}',
    };
    TableRow row(List<String> cells, {bool header = false}) => TableRow(
      children: [
        for (final c in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              c,
              style: header
                  ? TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: AppTextSize.label,
                    )
                  : null,
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.sm,
      children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(2)},
          children: [
            row(['Metric', 'Weight', 'Value', 'Points'], header: true),
            for (final p in parts)
              row([
                p.label,
                pct(p.weight),
                pctOrDash(p.normalized),
                p.points?.toStringAsFixed(3) ?? notMeasured,
              ]),
            if (pagesLoad != null)
              row([
                'Pages load (multiplier)',
                '×',
                pctOrDash(ratio),
                if (ratio == null)
                  notMeasured
                else
                  '× ${ratio.toStringAsFixed(2)}',
              ]),
          ],
        ),
        Text(
          "Recomputed from the metrics: $recomputed. The evaluator's own "
          'score is the one used for ranking, and the only judgement: '
          '${HealthThresholds.keepScore.toStringAsFixed(2)} or more keeps a '
          'source.',
        ),
      ],
    );
  }
}
