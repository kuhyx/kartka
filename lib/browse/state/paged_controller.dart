import 'package:flutter/foundation.dart';

/// One fetched page: its items and whether another page follows.
typedef PageResult<T> = ({List<T> items, bool hasNext});

/// Fetches 1-based page [page].
typedef PageFetcher<T> = Future<PageResult<T>> Function(int page);

/// Infinite-scroll state over a paged source call (popular/latest/search).
///
/// Guarantees: at most one fetch in flight, items deduplicated by [keyOf]
/// (sources often repeat an entry across page boundaries), no fetch after a
/// page reports `hasNext == false`, and results of a fetch started before
/// [reset] are dropped rather than appended to the new list.
class PagedController<T> extends ChangeNotifier {
  /// Creates a controller; nothing is fetched until [loadMore] is called.
  PagedController(this._fetch, {required Object Function(T item) keyOf})
    : _keyOf = keyOf;

  final Object Function(T item) _keyOf;
  PageFetcher<T> _fetch;
  final List<T> _items = [];
  final Set<Object> _keys = {};
  int _nextPage = 1;
  int _generation = 0;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;

  /// Items loaded so far, in source order.
  List<T> get items => List.unmodifiable(_items);

  /// Whether another page may exist.
  bool get hasNext => _hasNext;

  /// Whether a fetch is in flight.
  bool get loading => _loading;

  /// The error of the last failed fetch; cleared by the next attempt.
  Object? get error => _error;

  /// Whether [loadMore] would start a fetch right now.
  bool get canLoadMore => _hasNext && !_loading;

  /// Fetches the next page. A failed page is retried by calling this again.
  Future<void> loadMore() async {
    if (!canLoadMore) return;
    final generation = _generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _fetch(_nextPage);
      if (generation != _generation) return;
      for (final item in page.items) {
        if (_keys.add(_keyOf(item))) _items.add(item);
      }
      _nextPage++;
      _hasNext = page.hasNext;
    } on Object catch (e) {
      if (generation != _generation) return;
      _error = e;
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Clears everything (optionally switching to [fetch], e.g. a new search
  /// query) and loads page 1 again.
  Future<void> reset({PageFetcher<T>? fetch}) {
    _generation++;
    if (fetch != null) _fetch = fetch;
    _items.clear();
    _keys.clear();
    _nextPage = 1;
    _hasNext = true;
    _loading = false;
    _error = null;
    notifyListeners();
    return loadMore();
  }
}
