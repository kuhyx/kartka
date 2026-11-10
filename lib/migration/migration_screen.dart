import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/migration/migration_controller.dart';
import 'package:kartka/migration/migration_outcome.dart';

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
    appBar: AppBar(
      title: const Icon(Icons.swap_horiz, semanticLabel: 'Migrate to Atsumaru'),
    ),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _body(context, widget.controller),
    ),
  );

  Widget _body(BuildContext context, MigrationController c) {
    if (c.phase == MigrationPhase.unavailable) {
      return const EmptyMark(
        icon: Icons.cloud_off_outlined,
        semanticLabel:
            'Atsumaru is not available. Install the Atsumaru extension on '
            'the Suwayomi server, then open this again.',
      );
    }
    final busy =
        c.phase == MigrationPhase.searching ||
        c.phase == MigrationPhase.applying;
    if (c.rows.isEmpty && !busy) {
      return const EmptyMark(
        icon: Icons.done_all,
        semanticLabel:
            'Nothing to migrate. Every library entry is already on Atsumaru.',
      );
    }
    final done = c.phase == MigrationPhase.done;
    return Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (done || c.phase == MigrationPhase.failed)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: MigrationOutcome(
              migrated: c.migrated,
              failed: c.failed,
              backupKey: c.backupKey,
              error: done ? null : '${c.error}',
            ),
          ),
        Expanded(
          child: ListView(children: [for (final row in c.rows) _row(c, row)]),
        ),
        if (c.phase == MigrationPhase.ready)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton.icon(
              onPressed: c.canApply ? () => unawaited(c.apply()) : null,
              icon: const Icon(Icons.done_all, semanticLabel: 'Apply'),
              label: Text('${c.rows.where((r) => r.ticked).length}'),
            ),
          ),
      ],
    );
  }

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
      null when !row.searched => const SpokenLabel(
        semanticLabel: 'Searching…',
        child: RowSpinner(),
      ),
      null => const Icon(
        Icons.search_off,
        semanticLabel: 'No match on Atsumaru',
      ),
      final m => Row(
        spacing: AppSpacing.xs,
        children: [
          matchMark(exact: row.exact, closeLabel: 'Best match'),
          Flexible(child: Text(m.title)),
        ],
      ),
    };
    return CheckboxListTile(
      value: row.ticked,
      title: Text(row.entry.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          match,
          if (_sharing(c, row) case final others when others.isNotEmpty)
            Row(
              spacing: AppSpacing.xs,
              children: [
                const Icon(
                  Icons.merge,
                  semanticLabel: 'They merge: same Atsumaru entry as',
                ),
                Flexible(child: Text(others.join(', '))),
              ],
            ),
          if (row.error case final e?) Text(e),
        ],
      ),
      onChanged: candidate == null || c.phase != MigrationPhase.ready
          ? null
          : (v) => c.setTicked(row, ticked: v ?? false),
    );
  }
}
