import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/metric_explanations.dart';
import 'package:kartka/source_health/score_breakdown.dart';
import 'package:kartka/source_health/ui/health_badge.dart';

/// The status word and fill of a [MetricStatus]; neutral states are unfilled.
(String, Color?) metricStatusStyle(BuildContext context, MetricStatus s) {
  final c = statusColors(context);
  return switch (s) {
    MetricStatus.pass => ('Passes', c.success),
    MetricStatus.fail => ('Cuts', c.danger),
    MetricStatus.pending => ('Accruing', c.warning),
    MetricStatus.info => ('No cut', null),
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

/// The §5 score split into weighted parts, recomputed from the metrics.
class ScoreTable extends StatelessWidget {
  /// Creates a table of [parts].
  const new(this.parts, {super.key});

  /// The weighted parts.
  final List<ScorePart> parts;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (s, p) => s + (p.points ?? 0));
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
          ],
        ),
        Text(
          'Recomputed from the metrics: ${total.toStringAsFixed(2)}. The '
          "evaluator's own score is the one used for ranking.",
        ),
      ],
    );
  }
}
