import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kartka/core/models/category.dart';
import 'package:kartka/core/ui/confirm_mark.dart';
import 'package:kartka/core/ui/spoken_label.dart';
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
    final name = await askName(
      context,
      icon: Icons.new_label_outlined,
      semanticLabel: 'New category',
    );
    if (name != null) await _actions.create(name, _current);
  }

  Future<void> _rename(Category c) async {
    final name = await askName(
      context,
      icon: Icons.edit_outlined,
      semanticLabel: 'Rename',
      initial: c.name,
    );
    if (name != null) await _actions.rename(c, name);
  }

  Future<void> _delete(Category c) async {
    final ok = await confirmMark(
      context,
      icon: Icons.label_off_outlined,
      semanticLabel: 'Delete "${c.name}"?',
    );
    if (ok) await _actions.delete(c);
  }

  void _move(int from, int to) => unawaited(_actions.move(_current, from, to));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Icon(Icons.label, semanticLabel: 'Categories'),
      actions: [
        IconButton(
          icon: const Icon(Icons.add, semanticLabel: 'Add category'),
          onPressed: () => unawaited(_add()),
        ),
      ],
    ),
    body: StreamBuilder<List<Category>>(
      stream: _cats,
      builder: (context, snap) {
        final cats = _current = snap.data ?? const [];
        if (cats.isEmpty) {
          return const EmptyMark(
            icon: Icons.label_outline,
            semanticLabel: 'No categories yet',
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
          icon: const Icon(Icons.arrow_upward, semanticLabel: 'Move up'),
          onPressed: index == 0 ? null : onUp,
        ),
        IconButton(
          icon: const Icon(Icons.arrow_downward, semanticLabel: 'Move down'),
          onPressed: last ? null : onDown,
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, semanticLabel: 'Rename'),
          onPressed: onRename,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, semanticLabel: 'Delete'),
          onPressed: onDelete,
        ),
      ],
    ),
  );
}
