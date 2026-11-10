import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/downloads/queue/download_task.dart';
import 'package:kartka/downloads/ui/format.dart';

/// One queued, running or failed chapter, with its progress bar.
class QueueTile extends StatelessWidget {
  /// Creates the tile.
  const new({
    required this.task,
    required this.mangaTitle,
    required this.paused,
    required this.onCancel,
    required this.onRetry,
    super.key,
  });

  /// The chapter shown.
  final DownloadTask task;

  /// Display title of its manga.
  final String mangaTitle;

  /// Whether the whole queue is paused.
  final bool paused;

  /// Removes it from the queue.
  final VoidCallback onCancel;

  /// Requeues it after a failure.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = task.state;
    final failed = s.status == DownloadStatus.failed;
    final unknownTotal =
        s.status == DownloadStatus.downloading && s.pagesTotal == 0;
    return ListTile(
      title: Text(task.chapter.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(mangaTitle)),
              const SizedBox(width: AppSpacing.sm),
              SpokenLabel(
                semanticLabel: statusLine(s, paused: paused),
                child: ExcludeSemantics(
                  child: Icon(
                    queueStatusIcon(s.status, paused: paused),
                    size: 16,
                  ),
                ),
              ),
              if (s.status == DownloadStatus.downloading && s.pagesTotal > 0)
                Text(' ${s.pagesDone} / ${s.pagesTotal}'),
            ],
          ),
          if (failed && s.error != null)
            Text(
              redactUrlQueries(s.error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!failed)
            LinearProgressIndicator(value: unknownTotal ? null : s.fraction),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed)
            IconButton(
              icon: const Icon(Icons.refresh, semanticLabel: 'Retry'),
              onPressed: onRetry,
            ),
          IconButton(
            icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

/// The glyph for a queued chapter's status (its words are spoken only).
IconData queueStatusIcon(DownloadStatus status, {required bool paused}) =>
    switch (status) {
      DownloadStatus.queued when paused => Icons.pause_circle_outline,
      DownloadStatus.queued => Icons.schedule,
      DownloadStatus.failed => Icons.error_outline,
      DownloadStatus.done => Icons.download_done,
      DownloadStatus.none || DownloadStatus.downloading => Icons.downloading,
    };
