import 'package:design_system/design_system.dart';
import 'package:kartka/app/wait_watch.dart';
import 'package:material_ui/material_ui.dart';

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
    this.onScreen = true,
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

  /// Whether this slot is the one the reader is on. A paged view also lays
  /// out the slot next to the current page off screen; its spinner is not a
  /// wait the reader sees, so it is not timed as `reader.chapter`.
  final bool onScreen;

  /// Whether the neighbour is still being looked for, before its name is
  /// known (the chapter list is fetched again).
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = targetName;
    final failure = error;
    final spinner = CircularProgressIndicator(
      semanticsLabel: target == null ? 'Looking for the next chapter' : null,
    );
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
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
                semanticLabel: 'Could not open',
              ),
              if (target != null)
                Text(target, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(failure, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              IconButton.filled(
                style: IconButton.styleFrom(minimumSize: const Size.square(48)),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, semanticLabel: 'Retry'),
              ),
            ] else if (target != null || loading) ...[
              if (onScreen)
                WaitWatch(operation: 'reader.chapter', child: spinner)
              else
                spinner,
              if (target != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: AppSpacing.xs,
                  children: [
                    Icon(
                      forward ? Icons.skip_next : Icons.skip_previous,
                      color: muted?.color,
                      semanticLabel: forward ? 'Next' : 'Previous',
                    ),
                    Flexible(child: Text(target, style: muted)),
                  ],
                ),
              ],
            ] else ...[
              Icon(
                forward ? Icons.last_page : Icons.first_page,
                size: 48,
                color: muted?.color,
                semanticLabel: forward
                    ? 'No more chapters'
                    : 'Start of, no previous chapter',
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                currentName,
                style: forward ? muted : theme.textTheme.titleLarge,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
