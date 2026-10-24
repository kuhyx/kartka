import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/download_service.dart';

/// A [DownloadService] whose per-chapter states the test sets directly;
/// [watch] is live, and cancel / delete / enqueue are recorded.
class FakeDownloadService implements DownloadService {
  /// States by chapter url (missing = not downloaded).
  final Map<String, DownloadState> states = {};

  /// `cancel:<url>`, `delete:<url>` and `enqueue:<url>`, in order.
  final List<String> calls = [];

  final _changes = StreamController<void>.broadcast();

  /// Sets [url]'s state and tells the watchers.
  void set(String url, DownloadState state) {
    states[url] = state;
    _changes.add(null);
  }

  @override
  Stream<DownloadState> watch(MangaKey key, String chapterUrl) async* {
    yield states[chapterUrl] ?? DownloadState.none;
    await for (final _ in _changes.stream) {
      yield states[chapterUrl] ?? DownloadState.none;
    }
  }

  @override
  Future<void> enqueue(MangaKey key, ChapterInfo chapter) async {
    calls.add('enqueue:${chapter.url}');
    set(chapter.url, const DownloadState(status: DownloadStatus.queued));
  }

  @override
  Future<void> cancel(MangaKey key, String chapterUrl) async {
    calls.add('cancel:$chapterUrl');
    set(chapterUrl, DownloadState.none);
  }

  @override
  Future<void> deleteChapter(MangaKey key, String chapterUrl) async {
    calls.add('delete:$chapterUrl');
    set(chapterUrl, DownloadState.none);
  }

  @override
  Future<List<ChapterInfo>> downloadedChapters(MangaKey key) async => const [];

  // Browse uses only the members above.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
