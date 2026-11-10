import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/backup_import/backup_importer.dart';
import 'package:kartka/backup_import/import_plan.dart';
import 'package:kartka/core/ui/spoken_label.dart';

/// Tracker services the import binds, in display order (backup keys).
const List<String> _bound = ['anilist', 'mal', 'mangaupdates'];

/// One glyph/value line of the summary; [spoken] is the old worded label.
class _Row extends StatelessWidget {
  const new(this.icon, this.spoken, this.value);

  final IconData icon;
  final String spoken;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        SpokenLabel(semanticLabel: spoken, child: Icon(icon)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}

/// A section glyph in place of a worded header.
class _Section extends StatelessWidget {
  const new(this.icon, this.spoken);

  final IconData icon;
  final String spoken;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
    child: SpokenLabel(
      semanticLabel: spoken,
      child: Icon(icon, color: Theme.of(context).colorScheme.primary),
    ),
  );
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
    final bound = [for (final k in _bound) '$k ${s.trackersByService[k] ?? 0}']
        .join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Section(Icons.inventory_2_outlined, 'In the backup'),
        _Row(Icons.collections_bookmark, 'Library entries', '${s.entries}'),
        _Row(Icons.label_outline, 'Categories', '${s.categories}'),
        _Row(
          Icons.new_label_outlined,
          'Category memberships',
          '${s.memberships}',
        ),
        _Row(Icons.done_all, 'Chapters read', '${s.chaptersRead}'),
        _Row(Icons.sync_alt, 'Tracker links', bound),
        if (!bindTrackers && s.trackersImported > 0)
          const Icon(
            Icons.link_off,
            color: AppPalette.warning,
            semanticLabel: 'Tracking is not installed; tracker links skipped',
          ),
        if (others.isNotEmpty)
          _Row(
            Icons.block,
            'Other trackers (not imported)',
            others.entries.map((e) => '${e.key} ${e.value}').join(', '),
          ),
        if (s.notInLibrary > 0)
          _Row(
            Icons.history,
            'History-only records skipped',
            '${s.notInLibrary}',
          ),
        if (s.duplicates > 0)
          _Row(Icons.content_copy, 'Duplicates skipped', '${s.duplicates}'),
        if (unavailable.isNotEmpty) ...[
          const _Section(Icons.cloud_off, 'Source unavailable'),
          for (final u in unavailable)
            Row(
              children: [
                Expanded(
                  child: Text(u.name.isEmpty ? u.id : '${u.name} (${u.id})'),
                ),
                SpokenLabel(
                  semanticLabel: '${u.entries} entries',
                  child: ExcludeSemantics(child: Text('${u.entries}')),
                ),
              ],
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
      return const EmptyMark(
        icon: Icons.check_circle_outline,
        semanticLabel: 'Already imported',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Section(Icons.check_circle, 'Imported'),
        _Row(Icons.collections_bookmark, 'Library entries', '${r.entries}'),
        _Row(Icons.label_outline, 'Categories created', '${r.categories}'),
        _Row(
          Icons.new_label_outlined,
          'Category memberships',
          '${r.memberships}',
        ),
        _Row(Icons.done_all, 'Chapters marked read', '${r.readMarks}'),
        _Row(Icons.bookmark_outline, 'Reading positions', '${r.progress}'),
        _Row(Icons.sync_alt, 'Tracker links', '${r.bindings}'),
      ],
    );
  }
}
