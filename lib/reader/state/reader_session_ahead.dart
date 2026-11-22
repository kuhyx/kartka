part of 'reader_session.dart';

/// When the reader arrived on the trailing slot to wait, and on what.
class _EdgeWait {
  DateTime? since;
  String step = '';
}

/// Loading ahead (19643be5). The chapter-edge spinner waited on the chapter
/// list (fetched once page 1 is in), then on the next chapter's page list,
/// and a short chapter left the one after it unloaded. Now the stored list
/// names the next chapter at open, the chapter after a short one starts a
/// few pages early, and an edge wait over 1 s names the step it waited on.
extension _Ahead on ReaderSession {
  /// Loaded pages left after the current one below which the next chapter
  /// starts (or the look-ahead setting, when larger).
  static const _minPagesAhead = 5;

  /// Whether the reader is in the last loaded chapter or close to its end.
  bool get _nearEnd {
    if (segment == segments.length - 1) return true;
    final left = _flat.length - strip.offsetOf(segment) - page - 1;
    final ahead = settings.prefetchAhead;
    return left < (ahead > _minPagesAhead ? ahead : _minPagesAhead);
  }

  /// Gives every loaded chapter its neighbours in the current list.
  void _reneighbour() {
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      segments[i] = s.withNeighbours(neighboursOf(_chapters, s.url));
    }
  }

  /// [fresh] unless it lacks the opened chapter and the stored list in use
  /// has it (offline, the fallback list did not know it).
  List<ChapterInfo> _fresher(List<ChapterInfo> fresh) {
    final kept = neighboursOf(_chapters, chapterUrl).current != null;
    final known = neighboursOf(fresh, chapterUrl).current != null;
    return kept && !known ? _chapters : fresh;
  }

  /// The stored chapter list, once [firstPage] settled: when it names the
  /// opened chapter and the fresh list is still due, it names the
  /// neighbours and the next chapter starts loading at once.
  Future<void> _useStored(Future<void> firstPage) async {
    final List<ChapterInfo>? stored;
    try {
      stored = await deps.storedChapters?.stored(key);
    } on Object {
      return;
    }
    await firstPage;
    if (_disposed || !_listPending || stored == null) return;
    if (neighboursOf(stored, chapterUrl).current == null) return;
    _chapters = stored;
    _reneighbour();
    _maybeLoadNext();
    notifyListeners();
  }

  /// Drops loaded chapters the fresh list no longer puts next (one
  /// released after the stored list was saved), unless the reader is in
  /// them; the right one then loads.
  void _dropStale() {
    for (var k = segment + 1; k < segments.length; k++) {
      if (segments[k - 1].neighbours.next?.url == segments[k].url) continue;
      for (final s in segments.sublist(k)) {
        s.recorder.dispose();
      }
      segments.removeRange(k, segments.length);
      _flat = _flat.sublist(0, strip.pageCount);
      _cache?.dropFrom(_flat.length);
      _prefetch();
      return;
    }
  }

  /// The reader arrived on ([trailing]) or left the slot after the last
  /// page. Arriving retries a failure from a chapter earlier (a blip)
  /// instead of stopping on it, and starts timing the wait.
  void _edgeMoved({required bool trailing}) {
    if (!trailing) {
      _edge.since = null;
      return;
    }
    final retry = nextError != null;
    nextError = null;
    _edge
      ..since = deps.now()
      ..step = retry
          ? 'retry'
          : (_listPending && nextChapter == null ? 'list' : 'pages');
  }

  /// The next chapter's page 1 replaced the trailing slot: a wait of 1 s
  /// or more is logged as `reader.advance`, naming the step it waited on.
  void _edgeArrived() {
    final since = _edge.since;
    _edge.since = null;
    if (since == null) return;
    if (deps.now().difference(since) < const Duration(seconds: 1)) return;
    unawaited(
      deps.diagnostics?.append(
        DiagnosticEntry.failure(
          at: deps.now(),
          kind: 'reader.advance',
          error: ReaderLoadException(
            'ReaderProbe: next chapter waited on ${_edge.step}',
          ),
          stack: StackTrace.current,
          sourceId: sourceId,
          mangaUrl: mangaUrl,
          chapterUrl: segments.last.url,
        ),
      ),
    );
  }
}
