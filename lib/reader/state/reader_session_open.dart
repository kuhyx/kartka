part of 'reader_session.dart';

/// Opening a chapter. reader.open used to wait for the source lookup (up to
/// 5 s for a provider's first list), then the chapter list, then the pages
/// (971debc8). Now a downloaded chapter needs neither, an online one only
/// the source, and the list (Suwayomi fetches it from the site) starts
/// once page 1 is in: when it comes, it names the neighbours and lets the
/// next chapter load.
extension _Open on ReaderSession {
  Future<void> _openChapter() async {
    settings = await deps.prefs.settings();
    mode = await deps.prefs.effectiveMode(key);
    final found = deps.findSource(sourceId).then((s) => _source = s);
    var arrived = false;
    // The list starts once page 1 has arrived or failed: beside the open,
    // Suwayomi's list refresh (same rate-limited source) slowed the page
    // list from 0.12 s to 2.1 s and page 1 from 0.4 s to 1.3 s.
    final firstPage = Completer<void>();
    final listReady = _listReady = firstPage.future
        .then((_) => _chapterList(found))
        .then((list) {
          arrived = true;
          _chapters = list;
        });
    final ChapterPages loaded;
    try {
      loaded = await loadChapterPages(
        key: key,
        chapterUrl: chapterUrl,
        downloads: deps.downloads,
        source: found,
        cache: deps.pageLists,
        fresh: fresh,
      );
    } on ChapterUnavailable catch (e) {
      return _fail(e.message);
    } on SourceNeedsWebView catch (e) {
      // Known (971debc8): shown at once with Retry, never reported.
      return _fail(e.message);
    } on Object catch (e, stack) {
      final message = e is ReaderLoadException ? e.message : '$e';
      return _openFailed(e, stack, message);
    }
    final last = loaded.pages.length - 1;
    page = startAtEnd ? (last < 0 ? 0 : last) : await _resumePage(last);
    // The reader may have been left while this was loading.
    if (_disposed) return;
    _cache = PageCache(fetch: (i) => deps.loadImage(_flat[i]));
    _add(chapterUrl, loaded, landing: startAtEnd ? page : null);
    phase = ReaderPhase.ready;
    _prefetch();
    if (_flat.isEmpty) {
      firstPage.complete();
    } else {
      _cache!
          .get(page)
          .then<void>(
            (_) => firstPage.complete(),
            onError: (Object _) => firstPage.complete(),
          )
          .ignore();
    }
    // Until the list is in, the next chapter is not known: "loading".
    if (!arrived) {
      _listPending = true;
      _nextLoad = _afterList(listReady);
    }
    _maybeLoadNext();
    notifyListeners();
  }

  /// The list arrived after the first page showed: every loaded chapter
  /// gets its neighbours, and the next chapter may load.
  Future<void> _afterList(Future<void> listReady) async {
    await listReady;
    _nextLoad = null;
    _listPending = false;
    if (_disposed) return;
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      segments[i] = s.withNeighbours(neighboursOf(_chapters, s.url));
    }
    _maybeLoadNext();
    notifyListeners();
  }

  /// The source's chapter list; offline (or no source), what downloads
  /// knows. Never throws.
  Future<List<ChapterInfo>> _chapterList(Future<MangaSource?> found) async {
    try {
      final source = await found;
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
}
