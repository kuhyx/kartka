import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/library/state/library_controller.dart';
import 'package:kartka/library/ui/library_cell.dart';

/// The cover grid for the current query, or an empty state.
class LibraryGrid extends StatelessWidget {
  /// Creates the grid.
  const new({required this.controller, super.key});

  /// Screen state.
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.loaded) return const Center(child: CircularProgressIndicator());
    final items = c.visible;
    if (items.isEmpty) {
      return c.items.isEmpty
          ? const EmptyState(
              icon: Icons.collections_bookmark_outlined,
              title: 'Your library is empty',
              message: 'Add manga from Browse to see them here.',
            )
          : const EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'No matches',
              message: 'Change the tab, filters or search.',
            );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.55,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return LibraryCell(
          key: ValueKey(item.key),
          item: item,
          selected: c.selected.contains(item.key),
          coverLoader: c.deps.coverLoader,
          onSelect: () => c.toggle(item.key),
          onTap: c.selecting
              ? () => c.toggle(item.key)
              : () => context.push(mangaRoute(item.sourceId, item.mangaUrl)),
        );
      },
    );
  }
}
