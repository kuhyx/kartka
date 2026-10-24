import 'package:flutter/material.dart';
import 'package:kartka/core/models/models.dart';
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
          Text('$mangaTitle · ${statusLine(s, paused: paused)}'),
          if (!failed)
            LinearProgressIndicator(value: unknownTotal ? null : s.fraction),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry',
              onPressed: onRetry,
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
