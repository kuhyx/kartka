import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show WaitWatch;
import 'package:design_system/design_system.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/fit_pages.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/library/state/library_controller.dart';
import 'package:kartka/library/ui/library_cell.dart';
import 'package:material_ui/material_ui.dart';

/// The cover grid for the current query, paged sideways so it always fits
/// one screen, or an empty state; with [onRefresh], both can be pulled to
/// run it ("update all").
class LibraryGrid extends StatelessWidget {
  /// Creates the grid.
  const new({required this.controller, this.onRefresh, super.key});

  /// Screen state.
  final LibraryController controller;

  /// Runs on pull-to-refresh; `null` turns the pull off.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.loaded) {
      return const WaitWatch.centered('library.load');
    }
    final refresh = onRefresh;
    if (refresh == null) return _body(context);
    return RefreshIndicator(onRefresh: refresh, child: _body(context));
  }

  Widget _body(BuildContext context) {
    final c = controller;
    final items = c.visible;
    if (items.isEmpty) {
      return _pullable(
        c.items.isEmpty
            ? const EmptyMark(
                icon: Icons.collections_bookmark_outlined,
                semanticLabel: 'Your library is empty',
              )
            : const EmptyMark(
                icon: Icons.filter_alt_off_outlined,
                semanticLabel: 'No matches',
              ),
      );
    }
    return _pullable(
      FitPages(
        // A new tab starts on its first page.
        key: ValueKey(c.tab),
        itemCount: items.length,
        labelHeight: libraryLabelHeight(context),
        padding: const EdgeInsets.all(AppSpacing.sm),
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
      ),
    );
  }

  /// [child] at exactly the box height: it never scrolls, but with
  /// [onRefresh] it can still be pulled.
  Widget _pullable(Widget child) {
    if (onRefresh == null) return child;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(height: box.maxHeight, child: child),
      ),
    );
  }
}
