import 'dart:async';

/// Debounces page changes into progress writes.
///
/// Swiping through pages fires many changes per second; only the page the
/// reader settles on is written. Reaching the last page writes at once and
/// marks the chapter read exactly once per recorder.
class ProgressRecorder {
  /// Creates a recorder for a chapter of [pageCount] pages.
  new({
    required this.pageCount,
    required this.record,
    required this.markRead,
    this.debounce = const Duration(milliseconds: 600),
  });

  /// Pages in the chapter.
  final int pageCount;

  /// Persists the page the reader is on.
  final Future<void> Function(int page) record;

  /// Marks the whole chapter read.
  final Future<void> Function() markRead;

  /// How long a page must stay current before it is written.
  final Duration debounce;

  Timer? _timer;
  int? _pending;
  int? _lastWritten;
  bool _markedRead = false;
  bool _disposed = false;

  /// Reports that the reader now shows [page].
  void onPage(int page) {
    if (_disposed || page < 0 || page >= pageCount) return;
    _pending = page;
    _timer?.cancel();
    if (page == pageCount - 1) {
      unawaited(_reachEnd());
    } else {
      _timer = Timer(debounce, () => unawaited(flush()));
    }
  }

  Future<void> _reachEnd() async {
    await flush();
    if (_markedRead) return;
    _markedRead = true;
    await markRead();
  }

  /// Writes the pending page now, if any.
  Future<void> flush() async {
    _timer?.cancel();
    final page = _pending;
    _pending = null;
    if (page == null || page == _lastWritten) return;
    _lastWritten = page;
    await record(page);
  }

  /// Writes any pending page and stops accepting changes.
  void dispose() {
    unawaited(flush());
    _disposed = true;
  }
}
