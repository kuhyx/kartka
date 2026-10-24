import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/browse/ui/cover_image.dart';
import 'package:kartka/core/models/models.dart';

/// Cover, metadata, description and the action row of the detail screen.
class DetailHeader extends StatelessWidget {
  /// Creates the header; [read] is the current read set.
  const new({
    required this.controller,
    required this.details,
    required this.read,
    super.key,
  });

  /// Detail state.
  final MangaDetailController controller;

  /// Loaded details.
  final MangaDetails details;

  /// Read chapter urls.
  final Set<String> read;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (details.authors.isNotEmpty) details.authors.join(', '),
      details.status.name,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 112,
                  height: 160,
                  child: CoverImage(details.coverUrl),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(details.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(meta, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final g in details.genres) Chip(label: Text(g)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Actions(controller: controller, details: details, read: read),
          if (details.description case final d? when d.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(d, style: theme.textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const new({
    required this.controller,
    required this.details,
    required this.read,
  });

  final MangaDetailController controller;
  final MangaDetails details;
  final Set<String> read;

  void _open(BuildContext context, String chapterUrl) => unawaited(
    context.push(
      readRoute(controller.sourceId, controller.mangaUrl, chapterUrl),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final deps = BrowseScope.of(context);
    final first = firstUnread(controller.chapters, read);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StreamBuilder<ReadingProgress?>(
          stream: controller.progress(),
          builder: (context, snap) => snap.data == null
              ? const SizedBox.shrink()
              : FilledButton.icon(
                  key: const ValueKey('continue'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Continue'),
                  onPressed: () => _open(context, snap.data!.chapterUrl),
                ),
        ),
        if (first != null)
          OutlinedButton.icon(
            key: const ValueKey('read'),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Read'),
            onPressed: () => _open(context, first.url),
          ),
        StreamBuilder<bool>(
          stream: controller.inLibrary(),
          initialData: false,
          builder: (context, snap) {
            final inLibrary = snap.data!;
            return OutlinedButton.icon(
              key: const ValueKey('library'),
              icon: Icon(inLibrary ? Icons.favorite : Icons.favorite_border),
              label: Text(inLibrary ? 'In library' : 'Add to library'),
              onPressed: () =>
                  unawaited(controller.setInLibrary(add: !inLibrary)),
            );
          },
        ),
        if (deps.downloads != null)
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                onPressed: () =>
                    unawaited(controller.download(controller.chapters)),
                child: const Text('Download all'),
              ),
              MenuItemButton(
                onPressed: () => unawaited(
                  controller.download(unreadOf(controller.chapters, read)),
                ),
                child: const Text('Download unread'),
              ),
            ],
            builder: (context, menu, _) => OutlinedButton.icon(
              key: const ValueKey('download-menu'),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            ),
          ),
        for (final slot in deps.detailSlots)
          slot.build(context, controller.key, details),
      ],
    );
  }
}
