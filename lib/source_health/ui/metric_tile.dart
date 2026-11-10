import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/metric_explanations.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/score_breakdown.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

/// The glyph, spoken word and fill of a [MetricStatus]; neutral states are
/// unfilled.
(IconData, String, Color?) metricStatusStyle(
  BuildContext context,
  MetricStatus s,
) {
  final c = statusColors(context);
  return switch (s) {
    MetricStatus.pass => (Icons.check, 'Passes', c.success),
    MetricStatus.fail => (Icons.trending_down, 'Lowers score', c.danger),
    MetricStatus.warn => (Icons.warning_amber_rounded, 'Warns', c.warning),
    MetricStatus.pending => (Icons.hourglass_empty, 'Accruing', c.warning),
    MetricStatus.info => (Icons.info_outline, 'Info', null),
    MetricStatus.unknown => (Icons.remove, 'Not measured', null),
  };
}

/// One metric on the detail page: its glyph, value and status pill. The
/// name, meaning and threshold are spoken only.
class MetricTile extends StatelessWidget {
  /// Creates a tile for [explanation].
  const new(this.explanation, {super.key});

  /// What to show.
  final MetricExplanation explanation;

  @override
  Widget build(BuildContext context) {
    final e = explanation;
    final theme = Theme.of(context);
    final (icon, word, fill) = metricStatusStyle(context, e.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: SpokenLabel(
        semanticLabel:
            '${e.semanticLabel}: ${e.value}. ${e.meaning} ${e.threshold}',
        child: Row(
          spacing: AppSpacing.sm,
          children: [
            Icon(metricIcon(e.semanticLabel), color: theme.colorScheme.primary),
            Expanded(
              child: Wrap(
                spacing: AppSpacing.xs,
                children: [
                  if (e.value.isNotEmpty) Text(e.value),
                  for (final o in e.origins ?? const <String>[])
                    Icon(originIcon(o), key: Key('origin-$o')),
                ],
              ),
            ),
            StatusPill(icon: icon, semanticLabel: word, fill: fill),
          ],
        ),
      ),
    );
  }
}

/// The §5 score split into weighted parts and the pages-load multiplier,
/// recomputed from the metrics.
class ScoreTable extends StatelessWidget {
  /// Creates a table of [parts], times [pagesLoad] when the run has it and
  /// [profile] applies it; [profile] also gives the keep bar.
  const new(
    this.parts, {
    this.pagesLoad,
    this.profile = defaultScoringProfile,
    this.rankedLowBecause = const [],
    super.key,
  });

  /// [rankTierReasons] of the source: each ranks it below every source
  /// without it. Empty for most sources.
  final List<String> rankedLowBecause;

  /// The scoring profile the parts were weighted under.
  final ScoringProfile profile;

  /// The weighted parts.
  final List<ScorePart> parts;

  /// The multiplier; null on runs before `pagesLoad`.
  final PagesLoadMetric? pagesLoad;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final sum = parts.fold<double>(0, (s, p) => s + (p.points ?? 0));
    final applied = profile.pagesLoadMultiplier ? pagesLoad : null;
    final ratio = applied?.ratio;
    final recomputed = switch ((applied, ratio)) {
      (null, _) || (_, null) => sum.toStringAsFixed(2),
      (_, final x?) =>
        '${sum.toStringAsFixed(2)} × ${pct(x)} = '
            '${(sum * x).toStringAsFixed(2)}',
    };
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: child,
    );
    Widget head(IconData icon, String label) =>
        cell(Icon(icon, color: muted, semanticLabel: label));
    TableRow row(Widget first, List<String> cells) =>
        TableRow(children: [cell(first), for (final c in cells) cell(Text(c))]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.sm,
      children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(2)},
          children: [
            TableRow(
              children: [
                head(Icons.category_outlined, 'Metric'),
                head(Icons.balance, 'Weight'),
                head(Icons.straighten, 'Value'),
                head(Icons.functions, 'Points'),
              ],
            ),
            for (final p in parts)
              row(Icon(metricIcon(p.label), semanticLabel: p.label), [
                pct(p.weight),
                pctOrDash(p.normalized),
                p.points?.toStringAsFixed(3) ?? notMeasured,
              ]),
            if (applied != null)
              row(
                Icon(
                  metricIcon('Pages load'),
                  semanticLabel: 'Pages load (multiplier)',
                ),
                [
                  '×',
                  pctOrDash(ratio),
                  if (ratio == null)
                    notMeasured
                  else
                    '× ${ratio.toStringAsFixed(2)}',
                ],
              ),
          ],
        ),
        IconValue(
          Icons.functions,
          '$recomputed · ≥ ${profile.keepScore.toStringAsFixed(2)}',
          semanticLabel:
              'Recomputed under the ${profile.name} profile; '
              '${profile.keepScore.toStringAsFixed(2)} or more keeps a '
              'source${profile.cuts.isEmpty ? '' : _unlessCut}',
          key: const Key('recomputed'),
        ),
        if (_rankLine() case final line?)
          Icon(
            Icons.low_priority,
            color: statusColors(context).warning,
            semanticLabel: line,
          ),
      ],
    );
  }

  String? _rankLine() => switch (rankedLowBecause) {
    [] => null,
    [final one] =>
      'Ranked low: it $one, so it ranks below every source that does not. '
          '$_rankOnly',
    _ =>
      'Ranked lowest: it ${rankedLowBecause.join(' and ')}, so it ranks '
          'below every source with only one of these or neither. $_rankOnly',
  };

  static const _unlessCut = ', unless a cut switch applies';

  static const _rankOnly = 'The rank only: score and verdict are unchanged.';
}
