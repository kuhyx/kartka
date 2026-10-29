import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/migration/better/better_controller.dart';

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
    appBar: AppBar(title: const Text('Migrate to better sources')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _body(context, widget.controller),
    ),
  );

  Widget _body(BuildContext context, BetterSourcesController c) {
    final busy =
        c.phase == BetterPhase.loading || c.phase == BetterPhase.migrating;
    if (c.rows.isEmpty && !busy) {
      return const EmptyState(
        icon: Icons.done_all,
        title: 'Nothing to migrate',
        message: 'Every library entry is on a healthy source.',
      );
    }
    final pending = c.pending;
    return Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (_status(c) case final status?)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(status, style: Theme.of(context).textTheme.bodyLarge),
          ),
        Expanded(
          child: ListView(children: [for (final row in c.rows) _row(c, row)]),
        ),
        if (c.phase != BetterPhase.loading)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton(
              onPressed: pending == 0 || busy
                  ? null
                  : () => unawaited(_confirmAll(context, c, pending)),
              child: Text('Migrate all ($pending)'),
            ),
          ),
      ],
    );
  }

  static String? _status(BetterSourcesController c) {
    if (c.error case final e?) return 'Nothing moved: the backup failed ($e)';
    final key = c.backupKey;
    if (key == null) return null;
    final failed = c.failed > 0 ? ', ${c.failed} failed' : '';
    return 'Migrated ${c.migrated}$failed. Backup saved as $key';
  }

  Future<void> _confirmAll(
    BuildContext context,
    BetterSourcesController c,
    int count,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Migrate $count entries?'),
        content: const Text(
          'Each moves to its suggested source with its progress, categories '
          'and trackers. A backup of the library is saved first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Migrate'),
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
    final lines = <String>[
      if (target != null) '$from → ${target.record.name}',
      switch (match) {
        null when !row.searched => 'Searching…',
        null => 'No Keep source has this title',
        final m =>
          '${row.exact ? 'Exact' : 'Close'} match: ${m.title} · chapters '
              '${row.currentChapters ?? '?'} → ${row.targetChapters ?? '?'}',
      },
      'Why: ${row.reason}',
      ?row.error,
    ];
    return ListTile(
      title: Text(row.entry.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final l in lines) Text(l)],
      ),
      trailing: _action(c, row),
    );
  }

  Widget? _action(BetterSourcesController c, BetterRow row) {
    if (row.migrated) return const Text('Migrated');
    if (row.busy) {
      return const SizedBox.square(
        dimension: AppSpacing.lg,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (row.match == null) return null;
    return FilledButton.tonal(
      key: ValueKey('migrate-${row.entry.key}'),
      onPressed: c.phase == BetterPhase.ready && row.canMigrate
          ? () => unawaited(c.migrate(row))
          : null,
      child: const Text('Migrate'),
    );
  }
}
