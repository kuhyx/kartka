import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/cut_reasons.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/labels.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/health_badge.dart';

/// Opens the detail page of the source with this id.
typedef OpenSource = void Function(String sourceId);

/// One row of the ranking: rank, name, verdict, score, every metric and the
/// cut reasons in plain words. Activating it opens the detail page.
class SourceCard extends StatelessWidget {
  /// Creates a card for [record].
  new({required this.record, required this.onOpen, required this.nameOf})
    : super(key: ValueKey('source-${record.id}'));

  /// The source.
  final SourceHealthRecord record;

  /// Opens a source's detail page ([record]'s, or its subset-of target).
  final OpenSource onOpen;

  /// Names other sources (for the subset link).
  final SourceNameOf nameOf;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final subset = r.subsetOf;
    final warn = keptDespiteReasons(r);
    return Card(
      child: InkWell(
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
                        Text(
                          sourceLine(r),
                          style: TextStyle(
                            color: muted,
                            fontSize: AppTextSize.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(scoreText(r.score), style: theme.textTheme.titleMedium),
                  HealthBadge(verdict: r.verdict, rank: r.rank),
                ],
              ),
              if (r.needsBrowserEngine) const BrowserEngineChip(),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  _Metric('Uptime', uptimeText(r.uptime)),
                  _Metric('Latency', latencyText(r.latency)),
                  _Metric('Blocking', blockingText(r.blocking)),
                  _Metric('Coverage', coverageText(r.coverage)),
                  _Metric('Chapters', completenessText(r.completeness)),
                  _Metric('Image width', imageWidthText(r.imageQuality)),
                  _Metric('JPEG', jpegQualityText(r.imageQuality)),
                  _Metric('Available as', availabilityText(r.availability)),
                  if (r.pagesLoad != null)
                    _Metric('Pages load', pagesLoadText(r.pagesLoad)),
                ],
              ),
              if (subset != null)
                TextButton.icon(
                  icon: const Icon(Icons.call_split),
                  // Disabled when the covering source is not in the ranking.
                  onPressed: nameOf(subset.sourceId) == null
                      ? null
                      : () => onOpen(subset.sourceId),
                  label: Text(
                    'Subset of ${nameOf(subset.sourceId) ?? subset.sourceId} '
                    '(${pctOrDash(subset.overlap)})',
                  ),
                ),
              if (warn)
                Text('$keptDespiteHeading:', style: TextStyle(color: muted)),
              for (final why in explainCutReasons(r, nameOf: nameOf))
                if (warn) WarningLine(why) else Text(why),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const new(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: AppTextSize.caption,
          letterSpacing: 1.2,
        ),
      ),
      Text(value),
    ],
  );
}
