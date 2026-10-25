import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/labels.dart';

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

/// The warning chip for a source whose extension needs a browser engine.
/// It warns; it never means the source was cut.
class BrowserEngineChip extends StatelessWidget {
  /// Creates the chip.
  const new({super.key});

  /// The visible label.
  static const label = 'Needs browser engine';

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Warning: needs a browser engine',
    excludeSemantics: true,
    child: StatusPill(text: label, fill: statusColors(context).warning),
  );
}

/// Compact source-health badge for source lists: `#3 Cut`, with the
/// [BrowserEngineChip] under it when [needsBrowserEngine].
class HealthBadge extends StatelessWidget {
  /// Creates a badge; [rank] is omitted when the source is unranked.
  const new({
    required this.verdict,
    this.rank,
    this.needsBrowserEngine = false,
    super.key,
  });

  /// Evaluator verdict.
  final HealthVerdict verdict;

  /// 1-based rank, or null.
  final int? rank;

  /// Adds the "Needs browser engine" warning chip.
  final bool needsBrowserEngine;

  @override
  Widget build(BuildContext context) {
    final label = verdictLabel(verdict);
    final ranked = rank == null ? '' : 'rank $rank, ';
    final pill = Semantics(
      label: 'Source health: $ranked${verdict.name}',
      excludeSemantics: true,
      child: StatusPill(
        text: rank == null ? label : '#$rank $label',
        fill: verdictFill(context, verdict),
      ),
    );
    if (!needsBrowserEngine) return pill;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: AppSpacing.xs,
      children: [pill, const BrowserEngineChip()],
    );
  }
}

/// One reason a kept source was warned about: a warning icon, then [text].
class WarningLine extends StatelessWidget {
  /// Creates the line.
  const new(this.text, {super.key});

  /// The reason in words.
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: AppSpacing.xs,
    children: [
      Icon(
        Icons.warning_amber_rounded,
        size: AppTextSize.body,
        color: statusColors(context).warning,
        semanticLabel: 'Warning',
      ),
      Expanded(child: Text(text)),
    ],
  );
}
