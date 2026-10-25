import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/migration/migration_controller.dart';

/// "Migrate to Atsumaru": each entry with its best match, exact matches
/// pre-ticked. Nothing changes until the user taps Apply, which first
/// writes a backup.
class MigrationScreen extends StatefulWidget {
  /// Creates the screen; it loads and disposes [controller].
  const new({required this.controller, super.key});

  /// Drives the review.
  final MigrationController controller;

  @override
  State<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends State<MigrationScreen> {
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
    appBar: AppBar(title: const Text('Migrate to Atsumaru')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _body(context, widget.controller),
    ),
  );

  Widget _body(BuildContext context, MigrationController c) {
    if (c.phase == MigrationPhase.unavailable) {
      return const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Atsumaru is not available',
        message:
            'Install the Atsumaru extension on the Suwayomi server, then '
            'open this again.',
      );
    }
    final busy =
        c.phase == MigrationPhase.searching ||
        c.phase == MigrationPhase.applying;
    if (c.rows.isEmpty && !busy) {
      return const EmptyState(
        icon: Icons.done_all,
        title: 'Nothing to migrate',
        message: 'Every library entry is already on Atsumaru.',
      );
    }
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
        if (c.phase == MigrationPhase.ready)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton(
              onPressed: c.canApply ? () => unawaited(c.apply()) : null,
              child: Text('Apply (${c.rows.where((r) => r.ticked).length})'),
            ),
          ),
      ],
    );
  }

  static String? _status(MigrationController c) => switch (c.phase) {
    MigrationPhase.done =>
      'Migrated ${c.migrated}${c.failed > 0 ? ', ${c.failed} failed' : ''}. '
          'Backup saved as ${c.backupKey}',
    MigrationPhase.failed => 'Nothing changed: the backup failed (${c.error})',
    _ => null,
  };

  /// Titles of the other rows matched to [row]'s candidate (applying both
  /// merges them into one entry).
  static List<String> _sharing(MigrationController c, MigrationRow row) => [
    for (final other in c.rows)
      if (other != row &&
          row.candidate != null &&
          other.candidate?.url == row.candidate!.url)
        other.entry.title,
  ];

  Widget _row(MigrationController c, MigrationRow row) {
    final candidate = row.candidate;
    final match = switch (candidate) {
      null when !row.searched => 'Searching…',
      null => 'No match on Atsumaru',
      final m when row.exact => 'Exact match: ${m.title}',
      final m => 'Best match: ${m.title}',
    };
    return CheckboxListTile(
      value: row.ticked,
      title: Text(row.entry.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(match),
          if (_sharing(c, row) case final others when others.isNotEmpty)
            Text('Same Atsumaru entry as ${others.join(', ')}: they merge'),
          if (row.error case final e?) Text(e),
        ],
      ),
      onChanged: candidate == null || c.phase != MigrationPhase.ready
          ? null
          : (v) => c.setTicked(row, ticked: v ?? false),
    );
  }
}
