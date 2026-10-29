import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/browse/ui/chapter_download_button.dart';
import 'package:kartka/core/models/models.dart';

/// One chapter row: opens the reader; explicit buttons (focus stops, no
/// long-press) toggle the read mark and download, cancel or delete it.
/// Unread rows are at full brightness behind an accent dot; read rows are
/// dimmed to the muted text colour.
class ChapterTile extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.controller,
    required this.chapter,
    required this.read,
    required this.canDownload,
    super.key,
  });

  /// Detail state (actions).
  final MangaDetailController controller;

  /// The chapter shown.
  final ChapterInfo chapter;

  /// Whether the chapter is read.
  final bool read;

  /// Whether a downloads part is registered.
  final bool canDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final dimmed = TextStyle(color: muted);
    final subtitle = [
      ?chapter.scanlator,
      if (chapter.uploadedAt case final d?)
        d.toLocal().toIso8601String().substring(0, 10),
    ].join(' · ');
    return ListTile(
      key: ValueKey('chapter-${chapter.url}'),
      minLeadingWidth: AppSpacing.sm,
      leading: read
          ? const SizedBox(width: AppSpacing.sm)
          : SizedBox.square(
              key: ValueKey('unread-dot-${chapter.url}'),
              dimension: AppSpacing.sm,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppPalette.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
      title: Text(
        chapter.name,
        style: read ? dimmed : TextStyle(color: theme.colorScheme.onSurface),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, style: read ? dimmed : null),
      onTap: () => unawaited(
        context.push(
          readRoute(controller.sourceId, controller.mangaUrl, chapter.url),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: read ? 'Mark unread' : 'Mark read',
            icon: Icon(read ? Icons.check_circle : Icons.check_circle_outline),
            color: read ? theme.colorScheme.primary : muted,
            onPressed: () =>
                unawaited(controller.setRead(chapter, read: !read)),
          ),
          if (canDownload)
            ChapterDownloadButton(
              key: ValueKey('download-${chapter.url}'),
              controller: controller,
              chapter: chapter,
            ),
        ],
      ),
    );
  }
}
