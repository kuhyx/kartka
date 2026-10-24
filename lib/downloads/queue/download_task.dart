import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/keys.dart';

/// One chapter waiting in, or moving through, the download queue.
class DownloadTask {
  /// Creates a task; new tasks start [DownloadStatus.queued].
  const new({
    required this.mangaKey,
    required this.chapter,
    required this.enqueuedAt,
    this.state = const DownloadState(status: DownloadStatus.queued),
  });

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => DownloadTask(
    mangaKey: readString(json, 'mangaKey'),
    chapter: ChapterInfo.fromJson(readObject(json['chapter'])),
    enqueuedAt: readDate(json, 'enqueuedAt'),
    state: DownloadState.fromJson(readObject(json['state'])),
  );

  /// Manga the chapter belongs to.
  final MangaKey mangaKey;

  /// The chapter to download.
  final ChapterInfo chapter;

  /// When it was queued; the queue runs oldest first.
  final DateTime enqueuedAt;

  /// Current progress.
  final DownloadState state;

  /// Stable id, see [taskId].
  String get id => taskId(mangaKey, chapter.url);

  /// Source that serves the chapter.
  String get sourceId => sourceIdOf(mangaKey);

  /// Same task with a new [state].
  DownloadTask withState(DownloadState next) => DownloadTask(
    mangaKey: mangaKey,
    chapter: chapter,
    enqueuedAt: enqueuedAt,
    state: next,
  );

  /// JSON shape.
  Map<String, Object?> toJson() => {
    'mangaKey': mangaKey,
    'chapter': chapter.toJson(),
    'enqueuedAt': writeDate(enqueuedAt),
    'state': state.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is DownloadTask &&
      other.mangaKey == mangaKey &&
      other.chapter == chapter &&
      sameInstant(other.enqueuedAt, enqueuedAt) &&
      other.state == state;

  @override
  int get hashCode =>
      Object.hash(mangaKey, chapter, instantHash(enqueuedAt), state);

  @override
  String toString() => 'DownloadTask(${chapter.url} $state)';
}
