import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/library/library_routes.dart';
import 'package:kartka/library/state/library_controller.dart';
import 'package:kartka/library/state/library_deps.dart';
import 'package:kartka/library/ui/category_picker_dialog.dart';
import 'package:kartka/library/ui/library_app_bar.dart';
import 'package:kartka/library/ui/library_grid.dart';
import 'package:kartka/library/ui/library_options_sheet.dart';
import 'package:kartka/library/ui/library_swipe.dart';
import 'package:kartka/library/ui/update_progress_strip.dart';

/// The Library tab: category tabs over a cover grid, with search, sort,
/// filters and multi-select. Escape leaves selection or search.
class LibraryScreen extends StatefulWidget {
  /// Creates the screen over [deps].
  const new({required this.deps, super.key});

  /// Repositories, ports and clock.
  final LibraryDeps deps;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryController _c = LibraryController(widget.deps)..start();
  bool _searching = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _closeSearch() {
    setState(() => _searching = false);
    _c.query = _c.query.copyWith(search: '');
  }

  void _escape() {
    if (_c.selecting) {
      _c.clearSelection();
    } else if (_searching) {
      _closeSearch();
    }
  }

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    final batch = await _c.removeSelected();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Removed ${batch.entries.length} from library'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(_c.restore(batch)),
        ),
      ),
    );
  }

  Future<void> _updateAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final summary = await widget.deps.updater!.updateAll();
    messenger.showSnackBar(SnackBar(content: Text(summary.message)));
  }

  Future<void> _setCategories() async {
    final changes = await pickCategories(
      context,
      _c.categories,
      _c.selectionMembership(),
    );
    if (changes != null) await _c.setCategories(changes);
  }

  /// The selected tab: 0 is "All", then one per category in order.
  int get _tabIndex {
    final tab = _c.query.categoryId;
    if (tab == null) return 0;
    return _c.categories.indexWhere((c) => c.id == tab) + 1;
  }

  void _selectTab(int i) => _c.query = i == 0
      ? _c.query.copyWith(clearCategory: true)
      : _c.query.copyWith(categoryId: _c.categories[i - 1].id);

  void _step(int step) {
    final count = _c.categories.length + 1;
    final next = wrapIndex(_tabIndex, step, count);
    if (next != _tabIndex) _selectTab(next);
  }

  PreferredSizeWidget? _tabs() {
    final cats = _c.categories;
    if (cats.isEmpty) return null;
    return CategoryTabs(
      labels: ['All', for (final c in cats) c.name],
      index: _tabIndex,
      onSelect: _selectTab,
    );
  }

  @override
  Widget build(BuildContext context) {
    final updater = widget.deps.updater;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => Scaffold(
            appBar: LibraryAppBar(
              controller: _c,
              searching: _searching,
              onSearch: () => setState(() => _searching = true),
              onCloseSearch: _closeSearch,
              onOptions: () => unawaited(showLibraryOptions(context, _c)),
              onEditCategories: () =>
                  unawaited(context.push(libraryCategoriesRoute)),
              onSetCategories: () => unawaited(_setCategories()),
              onRemove: () => unawaited(_remove()),
              onUpdateAll: updater == null
                  ? null
                  : () => unawaited(_updateAll()),
              bottom: _tabs(),
            ),
            body: Column(
              children: [
                if (updater != null) UpdateProgressStrip(updater),
                Expanded(
                  child: CategorySwipe(
                    onStep: _step,
                    child: LibraryGrid(
                      controller: _c,
                      onRefresh: updater == null ? null : _updateAll,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
