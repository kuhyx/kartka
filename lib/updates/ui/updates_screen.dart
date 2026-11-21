import 'dart:async';

import 'package:kartka/app/fit_pages.dart';
import 'package:kartka/app/shown_wait_watch.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/library/ui/update_progress_strip.dart';
import 'package:kartka/updates/state/updates_controller.dart';
import 'package:kartka/updates/state/updates_deps.dart';
import 'package:kartka/updates/ui/update_groups.dart';
import 'package:kartka/updates/ui/update_sheet.dart';
import 'package:kartka/updates/ui/update_summary_mark.dart';
import 'package:kartka/updates/ui/update_tile.dart';
import 'package:material_ui/material_ui.dart';

/// The Updates tab: one tile per manga with new chapters, newest first, in a
/// grid that fits the screen (more pages sideways); a tile opens a sheet
/// with its chapters. "Update all" is on the refresh action and on pull.
class UpdatesScreen extends StatefulWidget {
  /// Creates the tab over [deps].
  const new({required this.deps, super.key});

  /// Feed, repositories, updater.
  final UpdatesDeps deps;

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  late final UpdatesController _c = UpdatesController(widget.deps)..start();

  /// Tiles warmed ahead: the sheet's own warm-up starts when it opens, and
  /// a tap there soon after still waited on the cold page list (1.7 s on
  /// the f4 sweep, 971debc8), so the first tiles warm as the feed shows.
  static const warmAhead = 3;
  final _warmed = <String>{};

  void _warmFirst(List<UpdateGroup> groups) {
    for (final g in groups.take(warmAhead)) {
      final r = likelyChapter(g);
      if (r != null && _warmed.add('${r.entry.key}\n${r.chapter.url}')) {
        widget.deps.warmChapter?.call(r.entry.key, r.chapter.url);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _updateAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final summary = await widget.deps.updater!.updateAll();
    messenger.showSnackBar(SnackBar(content: UpdateSummaryMark(summary)));
  }

  Widget _list(BuildContext context, Widget? _) {
    if (!_c.loaded) {
      return const ShownWaitWatch.centered('updates.load');
    }
    final rows = _c.rows;
    const physics = AlwaysScrollableScrollPhysics();
    if (rows.isEmpty) {
      // Scrollable, so the empty state can be pulled too.
      return LayoutBuilder(
        builder: (context, box) => ListView(
          physics: physics,
          children: [
            SizedBox(
              height: box.maxHeight,
              child: const EmptyMark(
                icon: Icons.new_releases_outlined,
                semanticLabel: 'No updates yet',
              ),
            ),
          ],
        ),
      );
    }
    final groups = groupByManga(rows);
    _warmFirst(groups);
    // Scrollable (but never scrolling) so the grid can be pulled too.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: physics,
        child: SizedBox(
          height: box.maxHeight,
          child: FitPages(
            itemCount: groups.length,
            labelHeight: updateTileLabelHeight,
            itemBuilder: (context, i) => UpdateTile(
              group: groups[i],
              covers: widget.deps.coverLoader,
              onTap: () => unawaited(
                showUpdateSheet(
                  context,
                  groups[i],
                  widget.deps.coverLoader,
                  warm: widget.deps.warmChapter,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updater = widget.deps.updater;
    final list = ListenableBuilder(listenable: _c, builder: _list);
    return Scaffold(
      appBar: AppBar(
        title: const Icon(
          Icons.new_releases_outlined,
          semanticLabel: 'Updates',
        ),
        actions: [
          if (updater != null)
            IconButton(
              icon: const Icon(
                Icons.refresh,
                semanticLabel: 'Check for updates',
              ),
              onPressed: () => unawaited(_updateAll()),
            ),
        ],
      ),
      body: Column(
        children: [
          if (updater != null) UpdateProgressStrip(updater),
          Expanded(
            child: updater == null
                ? list
                : RefreshIndicator(onRefresh: _updateAll, child: list),
          ),
        ],
      ),
    );
  }
}
