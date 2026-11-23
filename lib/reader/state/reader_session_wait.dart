part of 'reader_session.dart';

/// The shown page's wait (28fffd0a): timed by [PageWaitProbe], reported
/// by step, and held on [ReaderDeps.shownPages] so background work on the
/// same source waits for it.
extension _Wait on ReaderSession {
  /// The bytes of the page at [flat], in the queue's turn; see `image`.
  Future<Uint8List> _image(int flat) {
    final bytes = _cache!.waitFor(flat);
    if (flat == strip.offsetOf(segment) + page) {
      // The open's first shown page, or the first page past a chapter edge.
      final edge = _landing
          ? 'open'
          : (page == 0 && segment > 0 ? 'advance' : null);
      _landing = false;
      if (_cache!.peek(flat) == null) {
        _pageWait.asked(flat, bytes, edge: edge);
      }
    }
    return bytes.onError<Object>(_pageFailed);
  }

  /// Loads page [i], telling the probe when its fetch started: now, or
  /// when the warm or earlier load it joined did.
  Future<Uint8List> _fetchPage(int i) {
    final ref = _flat[i];
    final bytes = deps.loadImage(ref);
    final start = deps.imageStarted?.call(ref);
    _pageWait.started(i, at: start?.at, warm: start?.warm ?? false);
    return bytes;
  }

  /// The page at [current] is the one shown: while it loads, the gate
  /// holds background work on sources back.
  void _holdShown(int current) {
    final cache = _cache;
    final gate = deps.shownPages;
    if (cache == null || gate == null || cache.peek(current) != null) return;
    gate.hold(this, cache.get(current));
  }

  /// The page probe's report (28fffd0a): the shown page [flat] spun 1 s or
  /// more, mostly on [step]. Names the source and the image host's domain,
  /// never the time: the perf.slow report has it, and one text per step
  /// and source keeps it to one board ticket each.
  void _pageSlow(int flat, String step, Duration _) {
    final log = deps.diagnostics;
    if (log == null || flat >= _flat.length) return;
    final from = PageWaitProbe.domain(_flat[flat].imageUrl);
    ErrorReporter.of(log).report(
      'reader.pagewait',
      ReaderLoadException(
        'ReaderProbe: $sourceId page waited on $step from $from',
      ),
      stack: StackTrace.current,
      sourceId: sourceId,
    );
  }
}
