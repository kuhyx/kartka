import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/source_health_lookup.dart';

/// The word shown for a verdict.
String verdictLabel(HealthVerdict v) => switch (v) {
  HealthVerdict.keep => 'Keep',
  HealthVerdict.cut => 'Cut',
  HealthVerdict.pending => 'Pending',
};

/// The status fill for a verdict: keep = success, cut = danger,
/// pending = warning.
Color verdictFill(BuildContext context, HealthVerdict v) {
  final s = statusColors(context);
  return switch (v) {
    HealthVerdict.keep => s.success,
    HealthVerdict.cut => s.danger,
    HealthVerdict.pending => s.warning,
  };
}

/// The theme's status colours, falling back to the frozen palette.
AppStatusColors statusColors(BuildContext context) =>
    Theme.of(context).extension<AppStatusColors>() ??
    const AppStatusColors.standard();

/// A small label: [text] in `on-fill` on a filled [fill], or muted text in
/// an outline when [fill] is null (for neutral states, which have no fill).
class StatusPill extends StatelessWidget {
  /// Creates a pill.
  const new({required this.text, this.fill, super.key});

  /// Label.
  final String text;

  /// Background; null draws an outlined, neutral pill.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filled = fill;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled,
        border: filled == null ? Border.all(color: scheme.outline) : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: filled == null
                ? scheme.onSurfaceVariant
                : statusColors(context).onStatus,
            fontSize: AppTextSize.caption,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Compact source-health badge for source lists: `#3 Cut`.
class HealthBadge extends StatelessWidget {
  /// Creates a badge; [rank] is omitted when the source is unranked.
  const new({required this.verdict, this.rank, super.key});

  /// Evaluator verdict.
  final HealthVerdict verdict;

  /// 1-based rank, or null.
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final label = verdictLabel(verdict);
    final ranked = rank == null ? '' : 'rank $rank, ';
    return Semantics(
      label: 'Source health: $ranked${verdict.name}',
      excludeSemantics: true,
      child: StatusPill(
        text: rank == null ? label : '#$rank $label',
        fill: verdictFill(context, verdict),
      ),
    );
  }
}
