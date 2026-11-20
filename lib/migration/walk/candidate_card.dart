import 'package:design_system/design_system.dart';
import 'package:kartka/app/cached_cover.dart';
import 'package:kartka/migration/candidates/migration_candidate.dart';
import 'package:kartka/migration/walk/walk_parts.dart';
import 'package:material_ui/material_ui.dart';

/// One alternative: cover, title, source, chapters, newest date and match
/// strength. A tap ([onTap]) migrates the entry to it.
class CandidateCard extends StatelessWidget {
  /// Shows [candidate]; disabled when [onTap] is null.
  const new({
    required this.candidate,
    required this.loader,
    this.onTap,
    super.key,
  });

  /// The alternative.
  final MigrationCandidate candidate;

  /// Cover bytes.
  final CoverBytes? loader;

  /// Migrates to [candidate].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = candidate;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('candidate-${c.manga.url}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.md,
            children: [
              WalkCover(url: c.manga.coverUrl, loader: loader),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.xs,
                  children: [
                    Text(c.manga.title, style: theme.textTheme.titleMedium),
                    Text(
                      c.source.ref.name,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    ChapterFacts(chapters: c.chapters, newest: c.newest),
                    MatchMeter(c.score),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
