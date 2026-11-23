part of 'reader_session.dart';

/// Opening helpers, loaded chapters, prefetch and advancing into the next
/// chapter.
extension _Advance on ReaderSession {
  void _fail(String? message) {
    error = message;
    phase = ReaderPhase.failed;
    notifyListeners();
  }

  Future<Uint8List> _pageFailed(Object e, StackTrace stack) {
    if (deps.diagnostics case final log?) {
      ErrorReporter.of(log)
          .report('reader.page', e, stack: stack, sourceId: sourceId);
    }
    return Future.error(e, stack);
  }

  /// The probe's report: the pages the chapter opened on all failed.
  void _firstImagesFailed(Object e) => _logOpen(
    ReaderLoadException('ReaderProbe: first 3 images failed on $sourceId: $e'),
    StackTrace.current,
  );

  /// Fails the open with [message] (null: icon only), logging [e] as
  /// `reader.open`.
  void _openFailed(Object e, StackTrace stack, String? message) {
    _logOpen(e, stack);
    _fail(message);
  }

  void _logOpen(Object e, StackTrace stack) {
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
          record: (p) => _record(url, p, loaded.pages.length),
          markRead: () async => await deps.progress?.markRead(key, url),
        ),
      ),
    );
    _flat = [..._flat, ...loaded.pages];
  }

  /// Looks the chapter up at write time: a chapter list fetched again
  /// after a failure supplies the number the first one could not.
  Future<void> _record(String url, int page, int pageCount) async {
    await _listReady;
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
        pageCount: pageCount,
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
      ?..focus(
        current,
        prefetchIndices(current: current, total: total, ahead: ahead),
      )
      ..retain(retainWindow(current: current, total: total, ahead: ahead));
    _holdShown(current);
  }

  /// Starts loading the chapter after the last loaded one as soon as the
  /// reader is in that last chapter, or a few pages before it ([_nearEnd]),
  /// so its pages are known before the swipe that reaches them. One chapter
  /// at a time: chapters further on wait until the reader gets near.
  void _maybeLoadNext() {
    if (segments.isEmpty || _nextLoad != null || nextError != null) return;
    if (!_nearEnd) return;
    final next = nextChapter;
    if (next != null) {
      _nextLoad = _loadNext(next);
    } else if (segments.last.neighbours.current == null && !_listPending) {
      // Not in the chapter list (it failed at open): no next is unknown,
      // not the end, so ask the source again.
      _nextLoad = _findNext(segments.last.url);
    }
  }

  Future<void> _loadNext(ChapterInfo next) async {
    try {
      // The shown page first: the same source serves a few pages a second.
      await deps.shownPages?.idle();
      final loaded = await loadNextChapterPages(
        key: key,
        chapterUrl: next.url,
        downloads: deps.downloads,
        source: _source,
        cache: deps.pageLists,
        timeout: deps.advanceTimeout,
      );
      if (_disposed) return;
      // The fresh list may have named another next chapter meanwhile: that
      // one loads instead.
      if (nextChapter?.url == next.url) {
        _add(next.url, loaded);
        if (_onTrailing) {
          // The reader sat on the trailing slot, which is now this page 1.
          _onTrailing = false;
          segment = segments.length - 1;
          page = 0;
          segments.last.recorder.onPage(0);
          _edgeArrived();
        }
        _prefetch();
      }
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
      await deps.shownPages?.idle();
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
      _reneighbour();
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
    // The wait ended on the error; Retry starts a new one.
    _edge.since = null;
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
