import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/library/state/library_deps.dart';
import 'package:kartka/library/state/library_item.dart';
import 'package:kartka/library/ui/library_cover.dart';

/// One cover in the Library grid: title, unread badge, selection state.
///
/// A focus stop with a visible accent ring; Enter/Space activate [onTap],
/// long-press and secondary click call [onSelect] (the screen also offers a
/// keyboard path into selection, so long-press is never the only one).
class LibraryCell extends StatefulWidget {
  /// Creates a cell.
  const new({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onSelect,
    this.coverLoader,
    super.key,
  });

  /// The entry.
  final LibraryItem item;

  /// Whether it is in the multi-selection.
  final bool selected;

  /// Open (or toggle, while selecting).
  final VoidCallback onTap;

  /// Toggle selection.
  final VoidCallback onSelect;

  /// Cover loader.
  final CoverLoader? coverLoader;

  @override
  State<LibraryCell> createState() => _LibraryCellState();
}

class _LibraryCellState extends State<LibraryCell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final ring = _focused || widget.selected
        ? Border.all(color: AppPalette.accent, width: 2)
        : null;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onSelect,
        onSecondaryTap: widget.onSelect,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Container(
          foregroundDecoration: BoxDecoration(
            border: ring,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LibraryCover(
                      url: item.coverUrl,
                      loader: widget.coverLoader,
                    ),
                    if (item.unreadCount > 0)
                      Positioned(
                        top: AppSpacing.xs,
                        left: AppSpacing.xs,
                        child: _Badge(item.unreadCount),
                      ),
                    if (!item.sourceAvailable)
                      const Positioned(
                        bottom: AppSpacing.xs,
                        right: AppSpacing.xs,
                        child: Icon(
                          Icons.cloud_off,
                          color: AppPalette.warning,
                          semanticLabel: 'Source unavailable',
                        ),
                      ),
                    if (widget.selected)
                      const Positioned(
                        top: AppSpacing.xs,
                        right: AppSpacing.xs,
                        child: Icon(
                          Icons.check_circle,
                          color: AppPalette.accent,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const new(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppPalette.accent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: AppPalette.onFill),
      ),
    ),
  );
}
