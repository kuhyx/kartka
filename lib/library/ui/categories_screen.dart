import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/models/category.dart';
import 'package:kartka/library/state/category_actions.dart';
import 'package:kartka/library/state/library_deps.dart';
import 'package:kartka/library/ui/name_dialog.dart';

/// Create, rename, reorder (drag or Move up/down buttons) and delete
/// categories.
class CategoriesScreen extends StatefulWidget {
  /// Creates the screen over [deps].
  const new({required this.deps, super.key});

  /// Repositories and clock.
  final LibraryDeps deps;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final CategoryActions _actions = CategoryActions(widget.deps);
  late final Stream<List<Category>> _cats = widget.deps.repos.categories
      .watch();
  List<Category> _current = const [];

  Future<void> _add() async {
    final name = await askName(context, title: 'New category');
    if (name != null) await _actions.create(name, _current);
  }

  Future<void> _rename(Category c) async {
    final name = await askName(context, title: 'Rename', initial: c.name);
    if (name != null) await _actions.rename(c, name);
  }

  Future<void> _delete(Category c) async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete "${c.name}"?',
      message: 'Manga in it stay in your library.',
    );
    if (ok) await _actions.delete(c);
  }

  void _move(int from, int to) => unawaited(_actions.move(_current, from, to));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Categories'),
      actions: [
        IconButton(
          tooltip: 'Add category',
          icon: const Icon(Icons.add),
          onPressed: () => unawaited(_add()),
        ),
      ],
    ),
    body: StreamBuilder<List<Category>>(
      stream: _cats,
      builder: (context, snap) {
        final cats = _current = snap.data ?? const [];
        if (cats.isEmpty) {
          return const EmptyState(
            icon: Icons.label_outline,
            title: 'No categories yet',
            message: 'Add one to sort your library into tabs.',
          );
        }
        return ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: cats.length,
          onReorderItem: _move,
          itemBuilder: (context, i) => _Row(
            key: ValueKey(cats[i].id),
            index: i,
            category: cats[i],
            last: i == cats.length - 1,
            onUp: () => _move(i, i - 1),
            onDown: () => _move(i, i + 1),
            onRename: () => unawaited(_rename(cats[i])),
            onDelete: () => unawaited(_delete(cats[i])),
          ),
        );
      },
    ),
  );
}

class _Row extends StatelessWidget {
  const new({
    required this.index,
    required this.category,
    required this.last,
    required this.onUp,
    required this.onDown,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final int index;
  final Category category;
  final bool last;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: ReorderableDragStartListener(
      index: index,
      child: const Icon(Icons.drag_handle),
    ),
    title: Text(category.name),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Move up',
          icon: const Icon(Icons.arrow_upward),
          onPressed: index == 0 ? null : onUp,
        ),
        IconButton(
          tooltip: 'Move down',
          icon: const Icon(Icons.arrow_downward),
          onPressed: last ? null : onDown,
        ),
        IconButton(
          tooltip: 'Rename',
          icon: const Icon(Icons.edit_outlined),
          onPressed: onRename,
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ],
    ),
  );
}
