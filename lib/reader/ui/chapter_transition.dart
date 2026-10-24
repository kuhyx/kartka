import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The screen between chapters, shown past either end of a chapter.
class ChapterTransition extends StatelessWidget {
  /// A transition towards the next ([forward]) or previous chapter.
  const new({
    required this.forward,
    required this.currentName,
    this.targetName,
    this.onGo,
    super.key,
  });

  /// Whether this sits after the last page (true) or before the first.
  final bool forward;

  /// Name of the chapter being read.
  final String currentName;

  /// Name of the neighbouring chapter, or null when there is none.
  final String? targetName;

  /// Opens the neighbouring chapter.
  final VoidCallback? onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = targetName;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              forward ? 'Finished' : 'Start of',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(currentName, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            if (target == null)
              Text(forward ? 'No next chapter' : 'No previous chapter')
            else
              FilledButton(
                onPressed: onGo,
                child: Text('${forward ? 'Next' : 'Previous'}: $target'),
              ),
          ],
        ),
      ),
    );
  }
}
