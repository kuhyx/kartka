import 'package:flutter/material.dart';
import 'package:kartka/library/state/library_controller.dart';

/// The Library app bar in its three modes: normal, searching, selecting.
class LibraryAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the bar.
  const new({
    required this.controller,
    required this.searching,
    required this.onSearch,
    required this.onCloseSearch,
    required this.onOptions,
    required this.onEditCategories,
    required this.onSetCategories,
    required this.onRemove,
    this.onUpdateAll,
    this.bottom,
    super.key,
  });

  /// Screen state.
  final LibraryController controller;

  /// Whether the search field is open.
  final bool searching;

  /// Opens the search field.
  final VoidCallback onSearch;

  /// Closes the search field and clears the search.
  final VoidCallback onCloseSearch;

  /// Opens the sort and filter sheet.
  final VoidCallback onOptions;

  /// Opens category management.
  final VoidCallback onEditCategories;

  /// Opens the category picker for the selection.
  final VoidCallback onSetCategories;

  /// Removes the selection from the library.
  final VoidCallback onRemove;

  /// Runs "update all"; `null` hides the action.
  final VoidCallback? onUpdateAll;

  /// Category tabs.
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.selecting) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, semanticLabel: 'Exit selection'),
          onPressed: c.clearSelection,
        ),
        title: Text(
          '${c.selected.length}',
          semanticsLabel: '${c.selected.length} selected',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all, semanticLabel: 'Select all'),
            onPressed: c.selectAllVisible,
          ),
          IconButton(
            icon: const Icon(
              Icons.label_outline,
              semanticLabel: 'Set categories',
            ),
            onPressed: c.selected.isEmpty ? null : onSetCategories,
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              semanticLabel: 'Remove from library',
            ),
            onPressed: c.selected.isEmpty ? null : onRemove,
          ),
        ],
        bottom: bottom,
      );
    }
    return AppBar(
      title: searching
          ? TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, semanticLabel: 'Search library'),
              ),
              onChanged: (s) => c.query = c.query.copyWith(search: s),
            )
          : const Icon(Icons.menu_book, semanticLabel: 'Library'),
      actions: [
        if (searching)
          IconButton(
            icon: const Icon(Icons.close, semanticLabel: 'Close search'),
            onPressed: onCloseSearch,
          )
        else
          IconButton(
            icon: const Icon(Icons.search, semanticLabel: 'Search'),
            onPressed: onSearch,
          ),
        if (onUpdateAll != null)
          IconButton(
            icon: const Icon(Icons.refresh, semanticLabel: 'Update library'),
            onPressed: onUpdateAll,
          ),
        IconButton(
          icon: const Icon(Icons.filter_list, semanticLabel: 'Sort and filter'),
          onPressed: onOptions,
        ),
        IconButton(
          icon: const Icon(Icons.checklist, semanticLabel: 'Select'),
          onPressed: c.startSelecting,
        ),
        IconButton(
          icon: const Icon(Icons.label, semanticLabel: 'Edit categories'),
          onPressed: onEditCategories,
        ),
      ],
      bottom: bottom,
    );
  }
}
