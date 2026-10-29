import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/ui/cover_image.dart';
import 'package:kartka/core/models/models.dart';

/// The detail screen's header: collapsed to a cover thumbnail, the title
/// and one status line (authors · status) so the chapter list starts right
/// below it; a tap expands the tags and the description.
class DetailHeader extends StatefulWidget {
  /// Creates the header for [details].
  const new({required this.details, super.key});

  /// Loaded details.
  final MangaDetails details;

  @override
  State<DetailHeader> createState() => _DetailHeaderState();
}

class _DetailHeaderState extends State<DetailHeader> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.details;
    final meta = [
      if (d.authors.isNotEmpty) d.authors.join(', '),
      d.status.name,
    ].join(' · ');
    return InkWell(
      key: const ValueKey('detail-header'),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox(
                    width: AppSpacing.xxl,
                    height: AppSpacing.xxl * 1.4,
                    child: CoverImage(d.coverUrl),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        meta,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  semanticLabel: _expanded ? 'Hide details' : 'Show details',
                ),
              ],
            ),
            if (_expanded) ..._details(theme, d),
          ],
        ),
      ),
    );
  }

  List<Widget> _details(ThemeData theme, MangaDetails d) => [
    if (d.genres.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.md),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [for (final g in d.genres) Chip(label: Text(g))],
      ),
    ],
    if (d.description case final text? when text.isNotEmpty) ...[
      const SizedBox(height: AppSpacing.md),
      Text(text, style: theme.textTheme.bodyLarge),
    ],
  ];
}
