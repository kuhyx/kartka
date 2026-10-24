import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/backup_import/backup_importer.dart';
import 'package:kartka/backup_import/import_plan.dart';

const Set<String> _bound = {'anilist', 'mal', 'mangaupdates'};

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// One label/value line of the summary.
class _Row extends StatelessWidget {
  const new(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          Text(value, style: text.bodyMedium),
        ],
      ),
    );
  }
}

/// The dry-run summary: what is in the backup and what will happen.
class ImportPreview extends StatelessWidget {
  /// Creates the preview for [summary].
  const new(
    this.summary, {
    this.unavailable = const [],
    this.bindTrackers = true,
    super.key,
  });

  /// Dry-run counts.
  final ImportSummary summary;

  /// Entries whose source cannot open them right now.
  final List<UnavailableSource> unavailable;

  /// False when no tracking module is installed to take the AniList/MAL links.
  final bool bindTrackers;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final others = {...s.trackersByService}
      ..removeWhere((k, _) => _bound.contains(k));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('In the backup'),
        _Row('Library entries', '${s.entries}'),
        _Row('Categories', '${s.categories}'),
        _Row('Category memberships', '${s.memberships}'),
        _Row('Chapters read', '${s.chaptersRead}'),
        _Row('AniList links', '${s.trackersByService['anilist'] ?? 0}'),
        _Row('MyAnimeList links', '${s.trackersByService['mal'] ?? 0}'),
        _Row(
          'MangaUpdates links',
          '${s.trackersByService['mangaupdates'] ?? 0}',
        ),
        if (!bindTrackers && s.trackersImported > 0)
          Text(
            'Tracking is not installed, so AniList, MyAnimeList and '
            'MangaUpdates links are skipped. Import this file again once it '
            'is.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (others.isNotEmpty)
          _Row(
            'Other trackers (not imported)',
            others.entries.map((e) => '${e.key} ${e.value}').join(', '),
          ),
        if (s.notInLibrary > 0)
          _Row('History-only records skipped', '${s.notInLibrary}'),
        if (s.duplicates > 0) _Row('Duplicates skipped', '${s.duplicates}'),
        if (unavailable.isNotEmpty) ...[
          const SectionHeader('Source unavailable'),
          Text(
            'No installed source can open these. The entries are still '
            'imported, with their progress, and load once a source for them '
            'exists.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final u in unavailable)
            _Row(
              '${u.name.isEmpty ? 'Source' : u.name} (${u.id})',
              _plural(u.entries, 'entry', 'entries'),
            ),
        ],
      ],
    );
  }
}

/// The outcome after importing.
class ImportOutcome extends StatelessWidget {
  /// Creates the outcome for [result].
  const new(this.result, {super.key});

  /// What was written.
  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r.changedNothing) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Already imported',
        message: 'Everything in this backup is already in your library.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Imported'),
        _Row('Library entries', '${r.entries}'),
        _Row('Categories created', '${r.categories}'),
        _Row('Category memberships', '${r.memberships}'),
        _Row('Chapters marked read', '${r.readMarks}'),
        _Row('Reading positions', '${r.progress}'),
        _Row('Tracker links', '${r.bindings}'),
      ],
    );
  }
}
