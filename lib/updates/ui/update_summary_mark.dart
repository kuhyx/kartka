import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/library/ports.dart';

/// An update-all result as glyphs and counts, for a snackbar.
///
/// Paints no words: a check when nothing is new, else the new-chapter and
/// manga counts, then one glyph + count per kind of skipped manga. The
/// summary sentence ([UpdateSummary.message]) is only spoken.
class UpdateSummaryMark extends StatelessWidget {
  /// Draws [summary].
  const new(this.summary, {super.key});

  /// The update-all result.
  final UpdateSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final parts = <(IconData, int?)>[
      if (s.newChapters == 0)
        (Icons.done_all, null)
      else ...[
        (Icons.fiber_new_outlined, s.newChapters),
        (Icons.collections_bookmark_outlined, s.manga),
      ],
      if (s.failed > 0) (Icons.error_outline, s.failed),
      if (s.notChecked > 0) (Icons.cloud_off_outlined, s.notChecked),
      if (s.unavailable > 0) (Icons.extension_off_outlined, s.unavailable),
    ];
    final color = Theme.of(context).colorScheme.onInverseSurface;
    return SpokenLabel(
      semanticLabel: s.message,
      child: ExcludeSemantics(
        child: Wrap(
          spacing: AppSpacing.md,
          children: [
            for (final (icon, n) in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color),
                  if (n != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Text('$n'),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
