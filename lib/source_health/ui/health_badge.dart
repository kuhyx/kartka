import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

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

/// A small pill: [icon] (plus an optional number [text]) in `on-fill` on a
/// filled [fill], or muted in an outline when [fill] is null (for neutral
/// states, which have no fill). It paints no words: [semanticLabel] names it.
class StatusPill extends StatelessWidget {
  /// Creates a pill.
  const new({
    required this.icon,
    required this.semanticLabel,
    this.text,
    this.fill,
    super.key,
  });

  /// The glyph naming the state.
  final IconData icon;

  /// A number shown after the glyph (`#3`), or null.
  final String? text;

  /// What a screen reader says for the pill.
  final String semanticLabel;

  /// Background; null draws an outlined, neutral pill.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filled = fill;
    final fg = filled == null
        ? scheme.onSurfaceVariant
        : statusColors(context).onStatus;
    return SpokenLabel(
      semanticLabel: semanticLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.xs,
              children: [
                Icon(icon, size: AppTextSize.body, color: fg),
                if (text case final t?)
                  Text(
                    t,
                    style: TextStyle(
                      color: fg,
                      fontSize: AppTextSize.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
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

  /// The spoken label.
  static const label = 'Warning: needs a browser engine';

  @override
  Widget build(BuildContext context) => StatusPill(
    icon: Icons.web_outlined,
    semanticLabel: label,
    fill: statusColors(context).warning,
  );
}

/// The chip for a source this run only re-probed: it was hard-cut last run
/// and its one reachability request failed again.
class ReprobeChip extends StatelessWidget {
  /// Creates the chip.
  const new({super.key});

  /// The spoken label.
  static const label = 'Only re-probed this run: still unreachable';

  @override
  Widget build(BuildContext context) => StatusPill(
    icon: Icons.replay,
    semanticLabel: label,
    fill: statusColors(context).warning,
  );
}

/// Compact source-health badge for source lists: `#3` and the verdict
/// glyph on its colour, with the [BrowserEngineChip] under it when
/// [needsBrowserEngine].
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
    final ranked = rank == null ? '' : 'rank $rank, ';
    final pill = StatusPill(
      icon: verdictIcon(verdict),
      text: rank == null ? null : '#$rank',
      semanticLabel: 'Source health: $ranked${verdict.name}',
      fill: verdictFill(context, verdict),
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
