import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/metric_values.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

/// Every metric of [record] as glyph + value, for the ranking card. Each is
/// spoken as `<metric>: <worded value>` (`metric_text.dart`).
class MetricStrip extends StatelessWidget {
  /// Creates the strip for [record].
  const new(this.record, {super.key});

  /// The source.
  final SourceHealthRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final q = r.imageQuality;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        _m('Uptime', uptimeValue(r.uptime), uptimeText(r.uptime)),
        _m('Latency', latencyText(r.latency), latencyText(r.latency)),
        _m('Blocking', blockingValue(r.blocking), blockingText(r.blocking)),
        _m('Coverage', coverageValue(r.coverage), coverageText(r.coverage)),
        _m(
          'Chapters',
          completenessValue(r.completeness),
          completenessText(r.completeness),
        ),
        _m('Image width', imageWidthText(q), imageWidthText(q)),
        _m('JPEG', jpegQualityText(q), jpegQualityText(q)),
        AvailabilityMarks(r.availability),
        if (r.pagesLoad != null)
          _m(
            'Pages load',
            pagesLoadValue(r.pagesLoad),
            pagesLoadText(r.pagesLoad),
          ),
      ],
    );
  }

  Widget _m(String label, String painted, String spoken) =>
      IconValue(metricIcon(label), painted, semanticLabel: '$label: $spoken');
}

/// "Available as": the metric glyph, then one origin glyph per way of
/// reading the site (`0` when none, a dash when not measured).
class AvailabilityMarks extends StatelessWidget {
  /// Marks for [availability].
  const new(this.availability, {super.key});

  /// The metric, or null.
  final AvailabilityMetric? availability;

  @override
  Widget build(BuildContext context) {
    final origins = availableOrigins(availability);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SpokenLabel(
      semanticLabel: 'Available as: ${availabilityText(availability)}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.xs,
          children: [
            Icon(metricIcon('Available as'), color: muted),
            if (origins == null)
              const Text(notMeasured)
            else if (origins.isEmpty)
              const Text('0')
            else
              for (final o in origins) Icon(originIcon(o), key: Key('av-$o')),
          ],
        ),
      ),
    );
  }
}
