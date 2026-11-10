import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/core/ui/spoken_label.dart';
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
  late final LibraryController _c = LibraryController(
    widget.deps,
    schedule: beforeNextFrame,
  )..start();
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
    final n = batch.entries.length;
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Expanded(
              child: _Mark(
                Icons.delete_outline,
                '$n',
                'Removed $n from library',
              ),
            ),
            IconButton(
              color: AppPalette.accent,
              icon: const Icon(Icons.undo, semanticLabel: 'Undo'),
              onPressed: () {
                messenger.hideCurrentSnackBar();
                unawaited(_c.restore(batch));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final s = await widget.deps.updater!.updateAll();
    final fresh = s.newChapters > 0;
    messenger.showSnackBar(
      SnackBar(
        content: _Mark(
          fresh ? Icons.fiber_new_outlined : Icons.done_all,
          fresh ? '${s.newChapters}' : '',
          s.message,
        ),
      ),
    );
  }

  Future<void> _setCategories() async {
    final changes = await pickCategories(
      context,
      _c.categories,
      _c.selectionMembership(),
    );
    if (changes != null) await _c.setCategories(changes);
  }

  /// Tabs before the categories: 1 while "Default" shows, else 0.
  int get _lead => _c.hasDefaultTab ? 1 : 0;

  /// The selected tab: "Default" (when shown), then the categories.
  int get _tabIndex {
    final tab = _c.tab;
    if (tab == null) return 0;
    return _c.categories.indexWhere((c) => c.id == tab) + _lead;
  }

  void _selectTab(int i) => _c.query = i < _lead
      ? _c.query.copyWith(clearCategory: true)
      : _c.query.copyWith(categoryId: _c.categories[i - _lead].id);

  void _step(int step) {
    final count = _c.categories.length + _lead;
    final next = wrapIndex(_tabIndex, step, count);
    if (next != _tabIndex) _selectTab(next);
  }

  PreferredSizeWidget? _tabs() {
    final cats = _c.categories;
    if (cats.isEmpty) return null;
    return CategoryTabs(
      labels: [if (_lead == 1) null, for (final c in cats) c.name],
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

/// A snackbar glyph and count; [spoken] is the old sentence.
class _Mark extends StatelessWidget {
  const new(this.icon, this.count, this.spoken);

  final IconData icon;
  final String count;
  final String spoken;

  @override
  Widget build(BuildContext context) => SpokenLabel(
    semanticLabel: spoken,
    child: ExcludeSemantics(
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onInverseSurface),
          const SizedBox(width: AppSpacing.sm),
          Text(count),
        ],
      ),
    ),
  );
}
