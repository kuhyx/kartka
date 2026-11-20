import 'package:design_system/design_system.dart';
import 'package:kartka/app/cached_cover.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/migration/candidates/migration_candidate.dart';
import 'package:kartka/migration/same_manga.dart';
import 'package:kartka/migration/walk/walk_item.dart';
import 'package:material_ui/material_ui.dart';

/// A cover [width] wide at the 2:3 manga aspect, rounded.
class WalkCover extends StatelessWidget {
  /// The cover at [url] through [loader].
  const new({
    required this.url,
    required this.loader,
    this.width = 72,
    super.key,
  });

  /// Cover url.
  final String? url;

  /// Byte loader; a placeholder without one.
  final CoverBytes? loader;

  /// Painted width.
  final double width;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    child: SizedBox(
      width: width,
      height: width * 1.5,
      child: CachedCover(url: url, loader: loader),
    ),
  );
}

/// Chapter count and newest chapter date, as glyph + number pairs.
class ChapterFacts extends StatelessWidget {
  /// Shows [chapters] and [newest] (each only when known).
  const new({required this.chapters, required this.newest, super.key});

  /// Chapter count.
  final int? chapters;

  /// Newest chapter upload.
  final DateTime? newest;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Wrap(
      spacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(
          Icons.menu_book_outlined,
          size: 16,
          color: muted,
          semanticLabel: 'Chapters',
        ),
        Text('${chapters ?? '?'}'),
        if (newest case final d?) ...[
          Icon(
            Icons.schedule,
            size: 16,
            color: muted,
            semanticLabel: 'Newest chapter',
          ),
          Text(d.toLocal().toIso8601String().substring(0, 10)),
        ],
      ],
    );
  }
}

/// How sure the match is: signal bars plus a short bar, no words.
class MatchMeter extends StatelessWidget {
  /// Shows [score] (0-1).
  const new(this.score, {super.key});

  /// [SameManga.score] of the candidate.
  final double score;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (score) {
      >= strongMatch => (Icons.signal_cellular_alt, scheme.primary),
      >= fairMatch => (Icons.signal_cellular_alt_2_bar, scheme.tertiary),
      _ => (Icons.signal_cellular_alt_1_bar, scheme.error),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.xs,
      children: [
        Icon(
          icon,
          color: color,
          semanticLabel: 'Match ${(score * 100).round()}%',
        ),
        SizedBox(
          width: 64,
          child: LinearProgressIndicator(value: score, color: color),
        ),
      ],
    );
  }
}

/// The entry being migrated: cover, title, source, chapters, newest date.
class WalkHeader extends StatelessWidget {
  /// Shows [item] with covers from [loader].
  const new({required this.item, required this.loader, super.key});

  /// The current entry.
  final WalkItem item;

  /// Cover bytes.
  final CoverBytes? loader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.md,
      children: [
        WalkCover(url: item.entry.coverUrl, loader: loader, width: 96),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.xs,
            children: [
              Text(item.entry.title, style: theme.textTheme.titleLarge),
              Text(
                item.sourceName,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              ChapterFacts(
                chapters: item.found?.ownChapters,
                newest: item.found?.ownNewest,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Every searched source with how its search went: found, nothing, failed.
class LaneStrip extends StatelessWidget {
  /// Shows [lanes].
  const new(this.lanes, {super.key});

  /// The searched sources.
  final List<Lane> lanes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final l in lanes)
          Chip(
            avatar: switch (l.state) {
              LaneState.searching => SpokenLabel(
                semanticLabel: 'Searching ${l.source.ref.name}',
                child: const SizedBox.square(
                  dimension: AppSpacing.md,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              LaneState.found => Icon(
                Icons.check_circle_outline,
                color: scheme.primary,
                semanticLabel: 'Found on ${l.source.ref.name}',
              ),
              LaneState.empty => Icon(
                Icons.remove_circle_outline,
                semanticLabel: 'Nothing on ${l.source.ref.name}',
              ),
              LaneState.failed => Icon(
                Icons.error_outline,
                color: scheme.error,
                semanticLabel: 'Search failed on ${l.source.ref.name}',
              ),
            },
            label: Text(l.source.ref.name),
          ),
      ],
    );
  }
}
