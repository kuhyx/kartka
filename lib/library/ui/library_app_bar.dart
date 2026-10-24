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
          tooltip: 'Exit selection',
          icon: const Icon(Icons.close),
          onPressed: c.clearSelection,
        ),
        title: Text('${c.selected.length} selected'),
        actions: [
          IconButton(
            tooltip: 'Select all',
            icon: const Icon(Icons.select_all),
            onPressed: c.selectAllVisible,
          ),
          IconButton(
            tooltip: 'Set categories',
            icon: const Icon(Icons.label_outline),
            onPressed: c.selected.isEmpty ? null : onSetCategories,
          ),
          IconButton(
            tooltip: 'Remove from library',
            icon: const Icon(Icons.delete_outline),
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
              decoration: const InputDecoration(hintText: 'Search library'),
              onChanged: (s) => c.query = c.query.copyWith(search: s),
            )
          : const Text('Library'),
      actions: [
        if (searching)
          IconButton(
            tooltip: 'Close search',
            icon: const Icon(Icons.close),
            onPressed: onCloseSearch,
          )
        else
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: onSearch,
          ),
        IconButton(
          tooltip: 'Sort and filter',
          icon: const Icon(Icons.filter_list),
          onPressed: onOptions,
        ),
        IconButton(
          tooltip: 'Select',
          icon: const Icon(Icons.checklist),
          onPressed: c.startSelecting,
        ),
        IconButton(
          tooltip: 'Edit categories',
          icon: const Icon(Icons.label),
          onPressed: onEditCategories,
        ),
      ],
      bottom: bottom,
    );
  }
}
