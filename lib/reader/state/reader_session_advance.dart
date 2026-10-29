part of 'reader_session.dart';

/// Opening helpers, loaded chapters, prefetch and advancing into the next
/// chapter.
extension _Advance on ReaderSession {
  void _fail(String message) {
    error = message;
    phase = ReaderPhase.failed;
    notifyListeners();
  }

  Future<List<ChapterInfo>> _chapterList(MangaSource? source) async {
    try {
      if (source != null) return await source.chapters(mangaUrl);
    } on Object {
      // Offline: fall back to what downloads knows.
    }
    try {
      return await deps.downloads?.downloadedChapters(key) ?? const [];
    } on Object {
      return const [];
    }
  }

  Future<int> _resumePage(int last) async {
    final progress = deps.progress;
    if (progress == null) return 0;
    final saved = await progress
        .watch(key)
        .first
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    if (saved == null || saved.chapterUrl != chapterUrl) return 0;
    return saved.page < last ? saved.page : 0;
  }

  /// Appends the chapter at [url]; [landing] is a page arrived at, not read.
  void _add(String url, ChapterPages loaded, {int? landing}) {
    segments.add(
      ChapterSegment(
        url: url,
        neighbours: neighboursOf(_chapters, url),
        pages: loaded.pages,
        offline: loaded.offline,
        recorder: ProgressRecorder(
          pageCount: loaded.pages.length,
          landing: landing,
          record: (p) => _record(url, p),
          markRead: () async => await deps.progress?.markRead(key, url),
        ),
      ),
    );
    _flat = [..._flat, ...loaded.pages];
  }

  /// Looks the chapter up at write time: a chapter list fetched again
  /// after a failure supplies the number the first one could not.
  Future<void> _record(String url, int page) async {
    final n = neighboursOf(_chapters, url);
    final number = progressNumber(n.current, n.position);
    // Unknown chapter number (offline): only markRead may land.
    if (number == null) return;
    await deps.progress?.record(
      ReadingProgress(
        key: key,
        chapterUrl: url,
        chapterNumber: number,
        page: page,
        readAt: deps.now(),
      ),
    );
  }

  /// Fetches around the current page across chapter boundaries, so the next
  /// chapter's first pages are ready before the swipe that reaches them.
  void _prefetch() {
    final total = _flat.length;
    if (total == 0) return;
    final current = strip.offsetOf(segment) + page;
    final ahead = settings.prefetchAhead;
    _cache
      ?..prefetch([
        current,
        ...prefetchIndices(current: current, total: total, ahead: ahead),
      ])
      ..retain(retainWindow(current: current, total: total, ahead: ahead));
  }

  /// Starts loading the chapter after the last loaded one as soon as the
  /// reader is in that last chapter, so its pages are known a whole chapter
  /// before the swipe that reaches them. Only one chapter ahead: chapters
  /// further on wait until the reader gets there.
  void _maybeLoadNext() {
    if (segments.isEmpty || _nextLoad != null || nextError != null) return;
    if (segment < segments.length - 1) return;
    final next = nextChapter;
    if (next != null) {
      _nextLoad = _loadNext(next);
    } else if (segments.last.neighbours.current == null) {
      // Not in the chapter list (it failed at open): no next is unknown,
      // not the end, so ask the source again.
      _nextLoad = _findNext(segments.last.url);
    }
  }

  Future<void> _loadNext(ChapterInfo next) async {
    try {
      final loaded = await loadNextChapterPages(
        key: key,
        chapterUrl: next.url,
        downloads: deps.downloads,
        source: _source,
        timeout: deps.advanceTimeout,
      );
      if (_disposed) return;
      _add(next.url, loaded);
      if (_onTrailing) {
        // The reader sat on the trailing slot, which is now this page 1.
        _onTrailing = false;
        segment = segments.length - 1;
        page = 0;
        segments.last.recorder.onPage(0);
      }
      _prefetch();
    } on Object catch (e, stack) {
      _advanceFailed(e, stack, next.url);
    } finally {
      _nextLoad = null;
    }
    // A short chapter may already put the reader near the new end.
    _maybeLoadNext();
    notifyListeners();
  }

  /// Fetches the chapter list again for the chapter at [url], which the
  /// one fetched at open did not contain.
  Future<void> _findNext(String url) async {
    try {
      final source = _source ??= await deps.findSource(sourceId);
      if (source == null) {
        throw const ReaderLoadException(
          'The source is not available, so the next chapter is unknown.',
        );
      }
      final list = await source.chapters(mangaUrl).timeout(deps.advanceTimeout);
      // The reader may have been left while the list was fetched.
      if (_disposed) return;
      if (neighboursOf(list, url).current == null) {
        throw const ReaderLoadException(
          "This chapter is not in the source's chapter list.",
        );
      }
      _chapters = list;
      for (var i = 0; i < segments.length; i++) {
        final s = segments[i];
        segments[i] = s.withNeighbours(neighboursOf(list, s.url));
      }
    } on Object catch (e, stack) {
      _advanceFailed(e, stack, url);
    } finally {
      _nextLoad = null;
    }
    _maybeLoadNext();
    notifyListeners();
  }

  /// Shows [e] redacted on the trailing slot and logs it.
  void _advanceFailed(Object e, StackTrace stack, String chapterUrl) {
    nextError = redactUrlQueries(advanceFailureMessage(e));
    unawaited(
      deps.diagnostics?.append(
        DiagnosticEntry.failure(
          at: deps.now(),
          kind: 'reader.advance',
          error: e,
          stack: stack,
          sourceId: sourceId,
          mangaUrl: mangaUrl,
          chapterUrl: chapterUrl,
        ),
      ),
    );
  }
}
