import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/ui/browse_filters.dart';
import 'package:kartka/core/models/models.dart';

/// One source in the Browse grid: initial, health badge (or the bare
/// rank) and origin glyph on top, the name on one full-width line below.
/// Tap opens the catalogue, long-press the details sheet. Fills the cell
/// it is given.
class SourceTile extends StatelessWidget {
  /// Creates the tile.
  const new(this.source, this.summary, this.health, {super.key});

  /// The source shown.
  final SourceRef source;

  /// Its health, when known.
  final SourceHealthSummary? summary;

  /// Port that draws the badge; null without health data.
  final SourceHealthLookup? health;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rank = summary?.rank;
    // A stacked rank + "Needs browser engine" badge scales down to
    // illegible in a 3-column tile: the tile shows the rank pill and a
    // warning icon; the long-press sheet keeps the full badge.
    final s = summary;
    final engine = s?.needsBrowserEngine ?? false;
    final badge = health?.buildBadge(
      context,
      source.id,
      engine && s != null
          ? SourceHealthSummary(rank: s.rank, verdict: s.verdict)
          : s,
    );
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('source-${source.id}'),
        onTap: () => unawaited(context.push(sourceRoute(source.id))),
        onLongPress: () => unawaited(
          showModalBottomSheet<void>(
            context: context,
            builder: (_) => SourceSheet(source, summary, health),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                spacing: AppSpacing.sm,
                children: [
                  CircleAvatar(
                    radius: AppSpacing.md,
                    child: Text(_initial(source.name)),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: AppSpacing.lg,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child:
                            badge ??
                            (rank == null
                                ? const SizedBox.shrink()
                                : Text(
                                    '#$rank',
                                    style: theme.textTheme.labelMedium,
                                  )),
                      ),
                    ),
                  ),
                  Icon(
                    originIcons[source.origin],
                    size: AppSpacing.md,
                    color: theme.colorScheme.onSurfaceVariant,
                    semanticLabel: originLabels[source.origin],
                  ),
                  if (engine)
                    Icon(
                      Icons.warning_amber_rounded,
                      size: AppSpacing.md,
                      color:
                          (theme.extension<AppStatusColors>() ??
                                  const AppStatusColors.standard())
                              .warning,
                      semanticLabel: 'Needs browser engine',
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              // The name gets the tile's full width (beside the avatar a
              // 3-column tile cut "MangaDex" to "Manga…").
              Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

String _initial(String name) =>
    name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

/// Long-press details of a source: full name, language, rank and badge.
class SourceSheet extends StatelessWidget {
  /// Creates the sheet.
  const new(this.source, this.summary, this.health, {super.key});

  /// The source shown.
  final SourceRef source;

  /// Its health, when known.
  final SourceHealthSummary? summary;

  /// Port that draws the badge; null without health data.
  final SourceHealthLookup? health;

  @override
  Widget build(BuildContext context) {
    final rank = summary?.rank;
    return SafeArea(
      child: ListTile(
        leading: Icon(
          originIcons[source.origin],
          semanticLabel: originLabels[source.origin],
        ),
        title: Text(source.name),
        subtitle: Text(
          [source.lang.toUpperCase(), if (rank != null) '#$rank'].join(' · '),
        ),
        trailing: health?.buildBadge(context, source.id, summary),
      ),
    );
  }
}
