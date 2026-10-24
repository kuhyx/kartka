import 'dart:typed_data';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/reader/data/reader_prefs.dart';

/// Everything the reader talks to, injected so tests use fakes.
class ReaderDeps {
  /// Bundles the reader's collaborators.
  const new({
    required this.findSource,
    required this.progress,
    required this.prefs,
    required this.loadImage,
    this.downloads,
    this.now = DateTime.now,
  });

  /// The source with this id, or null when it is not installed.
  final Future<MangaSource?> Function(String sourceId) findSource;

  /// Where reading progress and read marks go.
  final ProgressRepository progress;

  /// Downloaded chapters, when the downloads part is installed.
  final DownloadRepository? downloads;

  /// Reader preferences.
  final ReaderPrefs prefs;

  /// Loads one page image (foundation's `PageImageLoader.load`).
  final Future<Uint8List> Function(PageRef page) loadImage;

  /// Clock for progress timestamps.
  final DateTime Function() now;
}
