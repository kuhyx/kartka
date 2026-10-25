import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/logic/chapter_order.dart';
import 'package:kartka/reader/logic/progress_recorder.dart';

/// One loaded chapter of the reader's strip, with its own progress writes.
class ChapterSegment {
  /// The loaded chapter at [url].
  const new({
    required this.url,
    required this.neighbours,
    required this.pages,
    required this.offline,
    required this.recorder,
  });

  /// Chapter URL.
  final String url;

  /// This chapter and its neighbours in reading order.
  final ChapterNeighbours neighbours;

  /// Pages in order.
  final List<PageRef> pages;

  /// Whether [pages] come from a download.
  final bool offline;

  /// Debounced progress writes and the read mark, for this chapter only.
  final ProgressRecorder recorder;

  /// Display name of the chapter.
  String get name => neighbours.current?.name ?? 'Chapter';
}
