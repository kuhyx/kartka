import 'dart:typed_data';

import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/reader/data/reader_prefs.dart';

/// Everything the reader talks to, injected so tests use fakes.
class ReaderDeps {
  /// Bundles the reader's collaborators.
  const new({
    required this.findSource,
    required this.prefs,
    required this.loadImage,
    this.progress,
    this.downloads,
    this.now = DateTime.now,
    this.diagnostics,
    this.advanceTimeout = const Duration(seconds: 30),
  });

  /// The source with this id, or null when it is not installed.
  final Future<MangaSource?> Function(String sourceId) findSource;

  /// Where reading progress and read marks go; null when the library part
  /// is not installed, in which case the reader still reads.
  final ProgressRepository? progress;

  /// Downloaded chapters, when the downloads part is installed.
  final DownloadRepository? downloads;

  /// Reader preferences.
  final ReaderPrefs prefs;

  /// Loads one page image (foundation's `PageImageLoader.load`).
  final Future<Uint8List> Function(PageRef page) loadImage;

  /// Clock for progress timestamps.
  final DateTime Function() now;

  /// Where failures to advance to the next chapter are logged.
  final DiagnosticsLog? diagnostics;

  /// How long the next chapter's page list may take before it counts as
  /// failed.
  final Duration advanceTimeout;
}
