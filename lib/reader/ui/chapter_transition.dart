import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The slot past either end of the loaded chapters.
///
/// The reader moves straight into a neighbouring chapter, so this only
/// shows while that chapter is loading, when it failed ([error] plus a
/// retry), or at the very start or end of the manga.
class ChapterTransition extends StatelessWidget {
  /// The edge after the last page ([forward]) or before the first.
  const new({
    required this.forward,
    required this.currentName,
    this.targetName,
    this.error,
    this.onRetry,
    super.key,
  });

  /// Whether this sits after the last page (true) or before the first.
  final bool forward;

  /// Name of the chapter at this edge.
  final String currentName;

  /// Name of the neighbouring chapter, or null when there is none.
  final String? targetName;

  /// Why the neighbour could not be opened (already redacted), if it failed.
  final String? error;

  /// Tries the neighbour again.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = targetName;
    final failure = error;
    final muted = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (target == null) ...[
              Text(forward ? 'Finished' : 'Start of', style: muted),
              const SizedBox(height: AppSpacing.xs),
              Text(currentName, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              Text(forward ? 'No next chapter' : 'No previous chapter'),
            ] else if (failure != null) ...[
              Text('Could not open $target', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(failure, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ] else ...[
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text('${forward ? 'Next' : 'Previous'}: $target', style: muted),
            ],
          ],
        ),
      ),
    );
  }
}
