import 'package:design_system/design_system.dart';
import 'package:kartka/app/cached_cover.dart';
import 'package:kartka/migration/candidates/migration_candidate.dart';
import 'package:kartka/migration/walk/page_previews.dart';
import 'package:kartka/migration/walk/walk_parts.dart';
import 'package:material_ui/material_ui.dart';

/// One alternative: cover, title, source, chapters, newest date, match
/// strength, its description and, behind an icon, its first pages. A tap
/// ([onTap]) migrates the entry to it.
class CandidateCard extends StatefulWidget {
  /// Shows [candidate]; disabled when [onTap] is null.
  const new({
    required this.candidate,
    required this.loader,
    this.pageLoader,
    this.onTap,
    super.key,
  });

  /// The alternative.
  final MigrationCandidate candidate;

  /// Cover bytes.
  final CoverBytes? loader;

  /// Page bytes for the preview; no preview icon without one.
  final PageBytes? pageLoader;

  /// Migrates to [candidate].
  final VoidCallback? onTap;

  @override
  State<CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends State<CandidateCard> {
  bool _previews = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.candidate;
    final pages = widget.pageLoader;
    final chapter = c.previewChapterUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('candidate-${c.manga.url}'),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.md,
            children: [
              WalkCover(url: c.manga.coverUrl, loader: widget.loader),
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
                    if (c.description case final d? when d.isNotEmpty)
                      Text(d, maxLines: 3, overflow: TextOverflow.ellipsis),
                    if (_previews && pages != null && chapter != null)
                      PagePreviews(
                        key: ValueKey('previews-${c.manga.url}'),
                        source: c.source,
                        chapterUrl: chapter,
                        loader: pages,
                      ),
                  ],
                ),
              ),
              if (pages != null && chapter != null)
                IconButton(
                  isSelected: _previews,
                  icon: const Icon(
                    Icons.photo_library_outlined,
                    semanticLabel: 'Page previews',
                  ),
                  onPressed: () => setState(() => _previews = !_previews),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
