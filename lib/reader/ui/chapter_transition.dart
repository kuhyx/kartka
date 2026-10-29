import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The slot past either end of the loaded chapters.
///
/// The reader moves straight into a neighbouring chapter, so this only
/// shows while that chapter is loading (it turns into the chapter's first
/// page on its own), when it failed ([error] plus a retry), or at the very
/// start or end of the manga.
class ChapterTransition extends StatelessWidget {
  /// The edge after the last page ([forward]) or before the first.
  const new({
    required this.forward,
    required this.currentName,
    this.targetName,
    this.error,
    this.onRetry,
    this.loading = false,
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

  /// Whether the neighbour is still being looked for, before its name is
  /// known (the chapter list is fetched again).
  final bool loading;

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
            if (failure != null) ...[
              Text(
                'Could not open ${target ?? 'the next chapter'}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(failure, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ] else if (target != null || loading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text(
                target == null
                    ? 'Looking for the next chapter'
                    : '${forward ? 'Next' : 'Previous'}: $target',
                style: muted,
              ),
            ] else if (forward) ...[
              Text('No more chapters', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(currentName, style: muted),
            ] else ...[
              Text('Start of', style: muted),
              const SizedBox(height: AppSpacing.xs),
              Text(currentName, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              const Text('No previous chapter'),
            ],
          ],
        ),
      ),
    );
  }
}
