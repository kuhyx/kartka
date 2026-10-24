import 'dart:convert';

import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/queue/download_task.dart';

/// The ordered, persistable download queue (pure state, no I/O).
///
/// Persisted as one JSON document in KeyValueStore so it survives restart.
class DownloadQueue {
  /// An empty, running queue.
  new();

  /// Decodes [toJson]. Tasks that were mid-download when the app stopped
  /// come back as queued; their stored pages are kept and skipped on resume.
  factory fromJson(Map<String, Object?> json) {
    final q = DownloadQueue()..paused = readBool(json, 'paused');
    for (final raw in json['tasks']! as List<Object?>) {
      final t = DownloadTask.fromJson(readObject(raw));
      final interrupted = t.state.status == DownloadStatus.downloading;
      q._tasks.add(interrupted ? t.withState(_requeued(t.state)) : t);
    }
    return q;
  }

  /// Decodes [encode]'s output; `null` (nothing stored yet) is empty.
  factory decode(String? raw) => raw == null
      ? DownloadQueue()
      : DownloadQueue.fromJson(readObject(jsonDecode(raw)));

  final List<DownloadTask> _tasks = [];

  /// When true no new chapter starts; running pages finish.
  bool paused = false;

  /// Tasks in queue order (oldest first).
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// The task with [id], if queued.
  DownloadTask? byId(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Appends [task]; a failed copy is requeued. Returns whether it changed.
  bool add(DownloadTask task) {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i < 0) {
      _tasks.add(task);
      return true;
    }
    final old = _tasks[i];
    if (old.state.status != DownloadStatus.failed) return false;
    _tasks[i] = old.withState(_requeued(old.state));
    return true;
  }

  /// Replaces the state of task [id]; unknown ids are ignored.
  void update(String id, DownloadState state) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i >= 0) _tasks[i] = _tasks[i].withState(state);
  }

  /// Removes and returns task [id].
  DownloadTask? remove(String id) {
    final t = byId(id);
    if (t != null) _tasks.remove(t);
    return t;
  }

  /// Queued tasks that may start now, in order.
  List<DownloadTask> runnable() => paused
      ? const []
      : [
          for (final t in _tasks)
            if (t.state.status == DownloadStatus.queued) t,
        ];

  /// JSON shape.
  Map<String, Object?> toJson() => {
    'paused': paused,
    'tasks': [for (final t in _tasks) t.toJson()],
  };

  /// [toJson] as a string for KeyValueStore.
  String encode() => jsonEncode(toJson());
}

DownloadState _requeued(DownloadState s) => DownloadState(
  status: DownloadStatus.queued,
  pagesDone: s.pagesDone,
  pagesTotal: s.pagesTotal,
);
