import 'package:kartka/downloads/queue/download_index.dart';
import 'package:kartka/downloads/queue/download_task.dart';

/// Everything the Downloads screen shows, emitted on every change.
class DownloadsSnapshot {
  /// Creates a snapshot.
  const new({required this.paused, required this.queue, required this.index});

  /// Whether the queue is paused.
  final bool paused;

  /// Queued, running and failed chapters, in queue order.
  final List<DownloadTask> queue;

  /// Chapters stored offline, with their sizes. Read-only by convention.
  final DownloadIndex index;
}
