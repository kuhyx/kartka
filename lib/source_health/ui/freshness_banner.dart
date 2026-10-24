import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/ranking.dart';
import 'package:kartka/source_health/thresholds.dart';
import 'package:kartka/source_health/ui/health_badge.dart';

/// "Last evaluated ..." plus a warning once results pass the stale limit.
class FreshnessBanner extends StatelessWidget {
  /// Creates a banner for results from [at], judged at [now].
  const new({required this.at, required this.now, super.key});

  /// When the evaluator last ran; null = never.
  final DateTime? at;

  /// The current time.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = at;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          when == null ? 'Never evaluated' : 'Last evaluated ${instant(when)}',
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: AppTextSize.label,
          ),
        ),
        if (isStale(when, now)) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(text: 'Stale', fill: statusColors(context).warning),
              Text(
                'Results are older than '
                '${HealthThresholds.staleAfter.inDays} days; the weekly '
                'source evaluator may have stopped.',
              ),
            ],
          ),
        ],
      ],
    );
  }
}
