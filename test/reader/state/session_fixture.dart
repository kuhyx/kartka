import 'dart:typed_data';

import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';

/// Chapters 1-3, newest first.
const sessionChapters = [
  ChapterInfo(url: '/c/3', name: 'Ch. 3', number: 3),
  ChapterInfo(url: '/c/2', name: 'Ch. 2', number: 2),
  ChapterInfo(url: '/c/1', name: 'Ch. 1', number: 1),
];

/// Builds sessions on chapter 2 of a fake manga and records what they do.
class SessionFixture {
  FakeProgress progress = FakeProgress();
  final List<String> fetched = [];

  /// When set, every page image load throws it.
  Error? imageError;
  final ReaderPrefs prefs = ReaderPrefs(MemoryKeyValueStore());
  final MemoryBlobStore diagnosticsStore = MemoryBlobStore();
  late final DiagnosticsLog diagnostics = DiagnosticsLog(diagnosticsStore);

  ReaderSession make({
    FakeSource? source,
    FakeDownloads? downloads,
    ReadingProgress? saved,
    String chapter = '/c/2',
    bool startAtEnd = false,
    Duration advanceTimeout = const Duration(seconds: 30),
  }) {
    progress = FakeProgress(initial: saved);
    final src =
        source ??
        FakeSource(
          chapterList: sessionChapters,
          pageMap: {'/c/2': fakePages('/c/2', 5)},
        );
    return ReaderSession(
      sourceId: 'fake',
      mangaUrl: '/m/1',
      chapterUrl: chapter,
      startAtEnd: startAtEnd,
      deps: ReaderDeps(
        diagnostics: diagnostics,
        advanceTimeout: advanceTimeout,
        findSource: (id) async => id == src.id ? src : null,
        progress: progress,
        downloads: downloads,
        prefs: prefs,
        loadImage: (p) async {
          fetched.add(p.imageUrl);
          if (imageError case final e?) throw e;
          return Uint8List(1);
        },
        now: () => DateTime.utc(2026, 10, 24),
      ),
    );
  }
}
