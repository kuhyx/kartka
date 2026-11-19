import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// Loads the encoded bytes of the page at [index].
typedef PageFetcher = Future<Uint8List> Function(int index);

/// In-memory cache of page image bytes, keyed by page index.
///
/// Holds futures rather than bytes so a page requested while its prefetch is
/// still in flight joins that request instead of starting a second one.
class PageCache {
  /// Creates a cache backed by [_fetch].
  new({required this._fetch});

  final PageFetcher _fetch;
  final Map<int, Future<Uint8List>> _entries = {};
  final Map<int, Uint8List> _loaded = {};
  final ListQueue<int> _queue = ListQueue();
  final Map<int, Completer<Uint8List>> _waiters = {};
  Future<Uint8List>? _gate;
  bool _draining = false;

  /// Whether [index] is cached or being fetched.
  bool contains(int index) => _entries.containsKey(index);

  /// The bytes of page [index] when they have arrived, else null: lets a
  /// page that is already loaded draw on its first frame.
  Uint8List? peek(int index) => _loaded[index];

  /// The bytes of page [index], fetching them on first use.
  ///
  /// A failed fetch is evicted so the next call retries.
  Future<Uint8List> get(int index) {
    final cached = _entries[index];
    if (cached != null) return cached;
    final future = _fetch(index);
    _entries[index] = future;
    _waiters.remove(index)?.complete(future);
    unawaited(
      future.then<void>(
        (bytes) {
          if (identical(_entries[index], future)) _loaded[index] = bytes;
        },
        onError: (Object _) {
          // Only evict our own entry: a retain + refetch may have replaced it.
          if (identical(_entries[index], future)) {
            _entries.remove(index)?.ignore();
          }
        },
      ),
    );
    return future;
  }

  /// The bytes of page [index] without starting a fetch beside the queue:
  /// a page not yet fetched waits for its turn, after the shown page and
  /// the look-aheads (the pager's off-screen neighbour, a webtoon page in
  /// the list's cache extent, a page the decode plan wants).
  Future<Uint8List> waitFor(int index) {
    final cached = _entries[index];
    if (cached != null) return cached;
    final waiter = _waiters.putIfAbsent(index, Completer.new);
    unawaited(_drain());
    return waiter.future;
  }

  /// Fetches [current] at once and the [ahead] pages after it, one at a
  /// time, once [current] has arrived or failed.
  ///
  /// The server rate-limits a source: four pages at once took up to 1.95 s
  /// each, one at a time 0.15 s (28fffd0a). Each call replaces the queue,
  /// so a jump goes first and the old look-aheads never start.
  void focus(int current, Iterable<int> ahead) {
    _gate = get(current);
    _queue
      ..clear()
      ..addAll(ahead);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    while (true) {
      final gate = _gate;
      if (gate != null) {
        await _settled(gate);
        // A focus while waiting set a new current: wait for that one.
        if (!identical(gate, _gate)) continue;
        _gate = null;
      }
      final next = _queue.isNotEmpty
          ? _queue.removeFirst()
          : _waiters.keys.firstOrNull;
      if (next == null) break;
      await _settled(get(next));
    }
    _draining = false;
  }

  static Future<void> _settled(Future<Uint8List> f) =>
      f.then<void>((_) {}, onError: (Object _) {});

  /// Drops every entry whose index is not in [keep].
  void retain(Set<int> keep) {
    _entries.removeWhere((index, _) => !keep.contains(index));
    _loaded.removeWhere((index, _) => !keep.contains(index));
  }

  /// Drops every entry.
  void clear() {
    _queue.clear();
    _waiters.clear();
    _gate = null;
    _entries.clear();
    _loaded.clear();
  }
}
