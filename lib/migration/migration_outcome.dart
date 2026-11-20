import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The result line of a migration run, word-free: a failed backup shows an
/// error glyph (the redacted error is spoken, never painted); a finished
/// run shows the migrated count, the failed count when any, and the backup
/// key.
class MigrationOutcome extends StatelessWidget {
  /// The outcome of a run that moved [migrated] entries ([failed] failed)
  /// after backing up to [backupKey], or whose backup failed with [error].
  const new({
    required this.migrated,
    required this.failed,
    this.backupKey,
    this.error,
    super.key,
  });

  /// Entries moved.
  final int migrated;

  /// Entries that failed to move.
  final int failed;

  /// Where the backup went; null before a run.
  final String? backupKey;

  /// Why the backup failed; nothing moved then.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge;
    final bad = theme.colorScheme.error;
    if (error case final e?) {
      return _line([
        Icon(
          Icons.error_outline,
          color: bad,
          semanticLabel: 'Nothing changed: the backup failed',
        ),
        errorMark(e),
      ]);
    }
    return _line([
      Icon(
        Icons.check_circle_outline,
        color: theme.colorScheme.primary,
        semanticLabel: 'Migrated',
      ),
      Text('$migrated', style: style),
      if (failed > 0) ...[
        Icon(Icons.error_outline, color: bad, semanticLabel: 'Failed'),
        Text('$failed', style: style),
      ],
      const Icon(Icons.backup_outlined, semanticLabel: 'Backup saved as'),
      Flexible(child: Text(backupKey ?? '', style: style)),
    ]);
  }

  static Widget _line(List<Widget> children) =>
      Row(spacing: AppSpacing.sm, children: children);
}

/// An error glyph speaking [error]: exception text is never painted.
Widget errorMark(String error) => Builder(
  builder: (context) => Icon(
    Icons.error_outline,
    color: Theme.of(context).colorScheme.error,
    semanticLabel: error,
  ),
);
