import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/state/refresh_outcome.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/spoken_label.dart';

/// A manga-detail refresh result for the snackbar, without painted words.
///
/// Failed: an error glyph and the (redacted) error. Nothing new: a check.
/// New chapters: a "new" glyph, the count and the chapter numbers. The
/// sentence ([refreshMessage]) is only spoken.
class RefreshMark extends StatelessWidget {
  /// Draws [outcome].
  const new(this.outcome, {super.key});

  /// What the refresh did.
  final RefreshOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onInverseSurface;
    final (icon, painted) = switch (outcome) {
      RefreshFailed(:final error) => (
        Icons.error_outline,
        redactUrlQueries('$error'),
      ),
      RefreshSucceeded(added: []) => (Icons.done_all, null),
      RefreshSucceeded(:final added) => (
        Icons.fiber_new_outlined,
        '${added.length} · ${newChapterNumbers(added)}',
      ),
    };
    return SpokenLabel(
      semanticLabel: refreshMessage(outcome),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(icon, color: color),
            if (painted != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(painted)),
            ],
          ],
        ),
      ),
    );
  }
}
