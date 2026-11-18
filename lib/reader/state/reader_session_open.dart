part of 'reader_session.dart';

/// Opening a chapter. reader.open used to wait for the source lookup (up to
/// 5 s for a provider's first list), then the chapter list, then the pages
/// (971debc8). Now a downloaded chapter needs neither, an online one only
/// the source, and the list (Suwayomi fetches it from the site) runs
/// alongside: when it comes after the first page, it names the neighbours
/// and lets the next chapter load.
extension _Open on ReaderSession {
  Future<void> _openChapter() async {
    settings = await deps.prefs.settings();
    mode = await deps.prefs.effectiveMode(key);
    final found = deps.findSource(sourceId).then((s) => _source = s);
    var arrived = false;
    final listReady = _listReady = _chapterList(found).then((list) {
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
      );
    } on ChapterUnavailable catch (e) {
      return _fail(e.message);
    } on ReaderLoadException catch (e, stack) {
      return _openFailed(e, stack, e.message);
    } on Object catch (e, stack) {
      return _openFailed(e, stack, '$e');
    }
    final last = loaded.pages.length - 1;
    page = startAtEnd ? (last < 0 ? 0 : last) : await _resumePage(last);
    // The reader may have been left while this was loading.
    if (_disposed) return;
    _cache = PageCache(fetch: (i) => deps.loadImage(_flat[i]));
    _add(chapterUrl, loaded, landing: startAtEnd ? page : null);
    phase = ReaderPhase.ready;
    _prefetch();
    // Until the list is in, the next chapter is not known: "loading".
    if (!arrived) _nextLoad = _afterList(listReady);
    _maybeLoadNext();
    notifyListeners();
  }

  /// The list arrived after the first page showed: every loaded chapter
  /// gets its neighbours, and the next chapter may load.
  Future<void> _afterList(Future<void> listReady) async {
    await listReady;
    _nextLoad = null;
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
