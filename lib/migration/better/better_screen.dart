import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/migration/better/better_controller.dart';
import 'package:kartka/migration/better/better_match.dart';
import 'package:kartka/migration/migration_outcome.dart';

/// "Migrate to better sources": every library entry whose source is cut,
/// blocking, missing or failing, with the best installed Keep source that
/// has the same title. Nothing moves until Migrate (one row) or a confirmed
/// Migrate all; both back the library up first.
class BetterSourcesScreen extends StatefulWidget {
  /// Creates the screen; it loads and disposes [controller].
  const new({required this.controller, super.key});

  /// Drives the screen.
  final BetterSourcesController controller;

  @override
  State<BetterSourcesScreen> createState() => _BetterSourcesScreenState();
}

class _BetterSourcesScreenState extends State<BetterSourcesScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Icon(
        Icons.auto_fix_high,
        semanticLabel: 'Migrate to better sources',
      ),
    ),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _body(context, widget.controller),
    ),
  );

  Widget _body(BuildContext context, BetterSourcesController c) {
    final busy =
        c.phase == BetterPhase.loading || c.phase == BetterPhase.migrating;
    if (c.rows.isEmpty && !busy) {
      return const EmptyMark(
        icon: Icons.done_all,
        semanticLabel:
            'Nothing to migrate. Every library entry is on a healthy source.',
      );
    }
    final pending = c.pending;
    return Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (c.error != null || c.backupKey != null)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: MigrationOutcome(
              migrated: c.migrated,
              failed: c.failed,
              backupKey: c.backupKey,
              error: c.error,
            ),
          ),
        Expanded(
          child: ListView(children: [for (final row in c.rows) _row(c, row)]),
        ),
        if (c.phase != BetterPhase.loading)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton.icon(
              onPressed: pending == 0 || busy
                  ? null
                  : () => unawaited(_confirmAll(context, c, pending)),
              icon: const Icon(Icons.done_all, semanticLabel: 'Migrate all'),
              label: Text('$pending'),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmAll(
    BuildContext context,
    BetterSourcesController c,
    int count,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.swap_horiz,
          semanticLabel:
              'Migrate $count entries? Each moves to its suggested source '
              'with its progress, categories and trackers. A backup of the '
              'library is saved first.',
        ),
        title: Text('$count'),
        actions: [
          IconButton(
            style: _square,
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
          ),
          IconButton.filled(
            style: _square,
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check, semanticLabel: 'Migrate'),
          ),
        ],
      ),
    );
    if (ok ?? false) await c.migrateAll();
  }

  Widget _row(BetterSourcesController c, BetterRow row) {
    final from = row.current?.name ?? row.entry.sourceId;
    final target = row.target;
    final match = row.match;
    return ListTile(
      title: Text(row.entry.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (target != null) Text('$from → ${target.record.name}'),
          switch (match) {
            null when !row.searched => const SpokenLabel(
              semanticLabel: 'Searching…',
              child: RowSpinner(),
            ),
            null => const Icon(
              Icons.search_off,
              semanticLabel: 'No Keep source has this title',
            ),
            final m => Row(
              spacing: AppSpacing.xs,
              children: [
                matchMark(exact: row.exact),
                Flexible(child: Text(m.title)),
                const Icon(Icons.menu_book_outlined, semanticLabel: 'chapters'),
                Text(
                  '${row.currentChapters ?? '?'} → '
                  '${row.targetChapters ?? '?'}',
                ),
              ],
            ),
          },
          Icon(reasonIcon(row.reason), semanticLabel: row.reason.label),
          if (row.error case final e?) Text(e),
        ],
      ),
      trailing: _action(c, row),
    );
  }

  Widget? _action(BetterSourcesController c, BetterRow row) {
    if (row.migrated) {
      return Icon(
        Icons.check_circle,
        color: Theme.of(context).colorScheme.primary,
        semanticLabel: 'Migrated',
      );
    }
    if (row.busy) return const RowSpinner();
    if (row.match == null) return null;
    return IconButton.filledTonal(
      key: ValueKey('migrate-${row.entry.key}'),
      style: _square,
      onPressed: c.phase == BetterPhase.ready && row.canMigrate
          ? () => unawaited(c.migrate(row))
          : null,
      icon: const Icon(Icons.swap_horiz, semanticLabel: 'Migrate'),
    );
  }
}

final ButtonStyle _square = IconButton.styleFrom(
  minimumSize: const Size.square(48),
);

/// The glyph naming why an entry should leave its source ([reason]).
IconData reasonIcon(MoveReason reason) => switch (reason) {
  MoveReason.notInstalled => Icons.extension_off_outlined,
  MoveReason.failedTest => Icons.bug_report_outlined,
  MoveReason.unreachable => Icons.cloud_off_outlined,
  MoveReason.cut => Icons.content_cut,
  MoveReason.challenge => Icons.gpp_maybe_outlined,
};
