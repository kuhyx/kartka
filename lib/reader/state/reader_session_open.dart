part of 'reader_session.dart';

/// Opening a chapter. reader.open used to wait for the source lookup (up to
/// 5 s for a provider's first list), then the chapter list, then the pages
/// (971debc8). Now a downloaded chapter needs neither, an online one only
/// the source, and the list (Suwayomi fetches it from the site) starts
/// once page 1 is in: when it comes, it names the neighbours and lets the
/// next chapter load.
extension _Open on ReaderSession {
  Future<void> _openChapter() async {
    final openStart = deps.now();
    var stepStart = deps.now();
    var slowestStep = '';
    var slowestDuration = Duration.zero;

    void recordStep(String name) {
      final elapsed = deps.now().difference(stepStart);
      if (elapsed > slowestDuration) {
        slowestDuration = elapsed;
        slowestStep = name;
      }
      stepStart = deps.now();
    }

    // Beside the page list: before it, two synced-kv reads took 0.33 s of
    // every open on the web build (971debc8).
    final prefs = (deps.prefs.settings(), deps.prefs.modeFor(key)).wait;
    final found = deps.findSource(sourceId).then((s) => _source = s);
    var arrived = false;
    // The list starts once page 1 has arrived or failed: beside the open,
    // Suwayomi's list refresh (same rate-limited source) slowed the page
    // list from 0.12 s to 2.1 s and page 1 from 0.4 s to 1.3 s.
    final firstPage = Completer<void>();
    // Held from the open's start until the first 3 pages are in: a
    // download beside the page list slowed it and page 1 past 1 s on 2 of
    // 3 opens, and one let in at page 1 queued page 2 (28fffd0a). A failed
    // open releases it (`_fail`).
    final landed = Completer<void>();
    deps.shownPages?.hold(this, landed.future);
    final listReady = _listReady = firstPage.future
        .then((_) => _chapterList(found))
        .then((list) {
          arrived = true;
          _chapters = _fresher(list);
        });
    // Read now, used once page 1 is in: it names the next chapter while
    // the fresh list is still on its way (19643be5).
    unawaited(_useStored(firstPage.future));
    final ChapterPages loaded;
    try {
      loaded = await loadChapterPages(
        key: key,
        chapterUrl: chapterUrl,
        downloads: deps.downloads,
        source: found,
        cache: deps.pageLists,
        fresh: fresh,
        onStep: recordStep,
      );
    } on ChapterUnavailable catch (e) {
      return _fail(e.message);
    } on SourceNeedsWebView {
      // Known (971debc8): the failed screen's icon and Retry at once, no
      // text (textgate), never reported.
      return _fail(null);
    } on Object catch (e, stack) {
      final message = e is ReaderLoadException ? e.message : '$e';
      return _openFailed(e, stack, message);
    }
    final (stored, chosen) = await prefs;
    settings = stored;
    mode = chosen ?? stored.defaultMode;
    recordStep('prefs');
    if (loaded.pages.isEmpty && !loaded.offline) {
      // Probe (971debc8): an empty chapter still opens (its end leads on to
      // the next one), but nothing said why it was empty.
      _logOpen(
        ReaderLoadException('ReaderProbe: $sourceId listed no pages'),
        StackTrace.current,
      );
    }
    final last = loaded.pages.length - 1;
    page = startAtEnd ? (last < 0 ? 0 : last) : await _resumePage(last);
    // The reader may have been left while this was loading.
    if (_disposed) return;
    final probe = FirstImagesProbe([
      for (var i = page; i < page + 3 && i <= last; i++) i,
    ], _firstImagesFailed);
    _cache = PageCache(fetch: (i) => probe.watch(i, _fetchPage(i)));
    _add(chapterUrl, loaded, landing: startAtEnd ? page : null);
    phase = ReaderPhase.ready;
    // Probe: log the single slowest step if the whole open up to ready
    // took >= 1 s.
    final total = deps.now().difference(openStart);
    final listSlow = total >= const Duration(seconds: 1);
    if (listSlow && slowestStep.isNotEmpty) _openSlow(slowestStep);
    _prefetch();
    // The shown page and the look-aheads it fetches next, at most 2.
    final ahead = settings.prefetchAhead < 2 ? settings.prefetchAhead : 2;
    final cache = _cache!;
    unawaited(
      [
        for (var i = page; i <= page + ahead && i <= last; i++)
          cache.waitFor(i).then<void>((_) {}, onError: _no),
      ].wait.whenComplete(landed.complete),
    );
    if (_flat.isEmpty) {
      firstPage.complete();
    } else {
      final ready = deps.now();
      _cache!.get(page).then<void>((_) {
        firstPage.complete();
        // 64f0bd6f: the list and page 1 each under 1 s, together over.
        final image = deps.now().difference(ready);
        if (listSlow || image >= const Duration(seconds: 1)) return;
        if (total + image < const Duration(seconds: 1)) return;
        final step = image > slowestDuration ? 'image' : slowestStep;
        _openSlow(step, what: 'open to page 1');
      }, onError: (Object _) => firstPage.complete()).ignore();
    }
    // Until the list is in, the next chapter is not known: "loading".
    if (!arrived) {
      _listPending = true;
      unawaited(_afterList(listReady));
    }
    _maybeLoadNext();
    notifyListeners();
  }

  /// The open probe's report: [what] (the open up to its page list, or
  /// up to page 1's bytes) took 1 s or more, mostly on [step]. One text
  /// per kind, step and source keeps it to one board ticket each; the
  /// two kinds never share one (`open waited on pages` is 64f0bd6f).
  void _openSlow(String step, {String what = 'open'}) => _logOpen(
    ReaderLoadException('ReaderProbe: $sourceId $what waited on $step'),
    StackTrace.current,
  );

  /// The list arrived after the first page showed: every loaded chapter
  /// gets its neighbours, a chapter loaded from the stored list that is no
  /// longer next goes, and the next chapter may load.
  Future<void> _afterList(Future<void> listReady) async {
    await listReady;
    _listPending = false;
    if (_disposed) return;
    _reneighbour();
    _dropStale();
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

  static void _no(Object _) {}
}
