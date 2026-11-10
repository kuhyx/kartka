import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/ranking.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

/// Reason chips (any selected reason matches) and the minimum-score slider.
class FilterBar extends StatelessWidget {
  /// Creates the bar over [query].
  const new({required this.query, required this.onChanged, super.key});

  /// Current query.
  final HealthQuery query;

  /// Called with the edited query.
  final ValueChanged<HealthQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final min = query.minScore.toStringAsFixed(2);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final r in HealthReason.values)
          FilterChip(
            key: Key('reason-${r.name}'),
            label: Icon(reasonIcon(r), semanticLabel: r.label),
            selected: query.reasons.contains(r),
            onSelected: (on) => onChanged(
              query.copyWith(
                reasons: on
                    ? {...query.reasons, r}
                    : query.reasons.difference({r}),
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconValue(
              Icons.filter_alt_outlined,
              min,
              semanticLabel: 'Min score',
            ),
            Slider(
              key: const Key('min-score'),
              value: query.minScore,
              divisions: 20,
              label: min,
              onChanged: (v) => onChanged(query.copyWith(minScore: v)),
            ),
          ],
        ),
      ],
    );
  }
}
