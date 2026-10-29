import 'dart:async';
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

  /// Starts fetching [indices] in the background.
  void prefetch(Iterable<int> indices) {
    for (final i in indices) {
      get(i).ignore();
    }
  }

  /// Drops every entry whose index is not in [keep].
  void retain(Set<int> keep) {
    _entries.removeWhere((index, _) => !keep.contains(index));
    _loaded.removeWhere((index, _) => !keep.contains(index));
  }

  /// Drops every entry.
  void clear() {
    _entries.clear();
    _loaded.clear();
  }
}
