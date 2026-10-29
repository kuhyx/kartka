import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/library/ui/update_progress_strip.dart';
import 'package:kartka/updates/state/updates_controller.dart';
import 'package:kartka/updates/state/updates_deps.dart';
import 'package:kartka/updates/ui/update_row_tiles.dart';

/// The Updates tab: new chapters of library manga by day, then manga, with
/// "update all" on the refresh action and on pull.
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

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _updateAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final summary = await widget.deps.updater!.updateAll();
    messenger.showSnackBar(SnackBar(content: Text(summary.message)));
  }

  Widget _list(BuildContext context, Widget? _) {
    if (!_c.loaded) return const Center(child: CircularProgressIndicator());
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
              child: const EmptyState(
                icon: Icons.new_releases_outlined,
                title: 'No updates yet — pull to check',
                message: 'New chapters of library manga show up here.',
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      physics: physics,
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      itemCount: rows.length,
      itemBuilder: (context, i) =>
          updateRowTile(context, rows[i], widget.deps.coverLoader),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updater = widget.deps.updater;
    final list = ListenableBuilder(listenable: _c, builder: _list);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        actions: [
          if (updater != null)
            IconButton(
              tooltip: 'Check for updates',
              icon: const Icon(Icons.refresh),
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
