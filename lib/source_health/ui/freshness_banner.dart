import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/ranking.dart';
import 'package:kartka/source_health/thresholds.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

/// A clock glyph and when the evaluator last ran, plus a warning pill once
/// results pass the stale limit.
class FreshnessBanner extends StatelessWidget {
  /// Creates a banner for results from [at], judged at [now].
  const new({required this.at, required this.now, super.key});

  /// When the evaluator last ran; null = never.
  final DateTime? at;

  /// The current time.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final when = at;
    final stamp = when == null ? notMeasured : instant(when);
    return Wrap(
      spacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconValue(
          Icons.schedule,
          stamp,
          semanticLabel: when == null ? 'Never evaluated' : 'Last evaluated',
          key: const Key('evaluated-at'),
        ),
        if (isStale(when, now))
          StatusPill(
            icon: Icons.warning_amber_rounded,
            semanticLabel:
                'Stale: results are older than '
                '${HealthThresholds.staleAfter.inDays} days',
            fill: statusColors(context).warning,
          ),
      ],
    );
  }
}
