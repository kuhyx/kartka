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

  Future<void> _setCategories() async {
    final changes = await pickCategories(
      context,
      _c.categories,
      _c.selectionMembership(),
    );
    if (changes != null) await _c.setCategories(changes);
  }

  PreferredSizeWidget? _tabs() {
    final cats = _c.categories;
    if (cats.isEmpty) return null;
    final tab = _c.query.categoryId;
    final index = tab == null ? 0 : cats.indexWhere((c) => c.id == tab) + 1;
    return PreferredSize(
      preferredSize: const Size.fromHeight(kTextTabBarHeight),
      child: DefaultTabController(
        key: ValueKey([for (final c in cats) c.id].join('\n')),
        length: cats.length + 1,
        initialIndex: index,
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          onTap: (i) => _c.query = i == 0
              ? _c.query.copyWith(clearCategory: true)
              : _c.query.copyWith(categoryId: cats[i - 1].id),
          tabs: [
            const Tab(text: 'All'),
            for (final c in cats) Tab(text: c.name),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
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
            bottom: _tabs(),
          ),
          body: LibraryGrid(controller: _c),
        ),
      ),
    ),
  );
}
