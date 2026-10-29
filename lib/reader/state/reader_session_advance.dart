part of 'reader_session.dart';

/// Opening helpers, loaded chapters, prefetch and advancing into the next
/// chapter.
extension _Advance on ReaderSession {
  void _fail(String message) {
    error = message;
    phase = ReaderPhase.failed;
    notifyListeners();
  }

  /// Fails the open with [message], logging [e] as `reader.open`.
  void _openFailed(Object e, StackTrace stack, String message) {
    unawaited(
      deps.diagnostics?.append(
        DiagnosticEntry.failure(
          at: deps.now(),
          kind: 'reader.open',
          error: e,
          stack: stack,
          sourceId: sourceId,
          mangaUrl: mangaUrl,
          chapterUrl: chapterUrl,
        ),
      ),
    );
    _fail(message);
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
    final n = neighboursOf(_chapters, url);
    segments.add(
      ChapterSegment(
        url: url,
        neighbours: n,
        pages: loaded.pages,
        offline: loaded.offline,
        recorder: ProgressRecorder(
          pageCount: loaded.pages.length,
          landing: landing,
          record: (p) => _record(n, url, p),
          markRead: () async => await deps.progress?.markRead(key, url),
        ),
      ),
    );
    _flat = [..._flat, ...loaded.pages];
  }

  Future<void> _record(ChapterNeighbours n, String url, int page) async {
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

  /// Starts loading the next chapter once the reader is within the prefetch
  /// window of the last loaded page ([force]: right away, for a retry).
  void _maybeLoadNext({bool force = false}) {
    final next = nextChapter;
    if (next == null || _nextLoad != null || nextError != null) return;
    final remaining = _flat.length - 1 - (strip.offsetOf(segment) + page);
    if (!force && remaining > settings.prefetchAhead) return;
    _nextLoad = _loadNext(next);
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
            chapterUrl: next.url,
          ),
        ),
      );
    } finally {
      _nextLoad = null;
    }
    // A short chapter may already put the reader near the new end.
    _maybeLoadNext();
    notifyListeners();
  }
}
