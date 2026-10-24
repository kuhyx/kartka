import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kartka/core/models/manga.dart';
import 'package:kartka/core/models/source_ref.dart';
import 'package:kartka/core/source/manga_source.dart';

/// Page-1 search result of one source in a global search.
@immutable
class SourceSearchState {
  /// Creates a state; a fresh search starts with [loading] true.
  const SourceSearchState(
    this.source, {
    this.loading = false,
    this.items = const [],
    this.error,
  });

  /// The searched source.
  final SourceRef source;

  /// Whether this source's request is still in flight.
  final bool loading;

  /// First-page hits.
  final List<MangaSummary> items;

  /// Failure (including a timeout) for this source only.
  final Object? error;
}

/// Searches every source at once and publishes each source's result as soon
/// as it arrives. A slow or failing source never blocks or blanks the others:
/// each has its own [timeout] and its own error.
class GlobalSearchController extends ChangeNotifier {
  /// Creates a controller over [sources] (display order is kept).
  GlobalSearchController(
    List<MangaSource> sources, {
    this.timeout = const Duration(seconds: 20),
  }) : _sources = List.unmodifiable(sources);

  final List<MangaSource> _sources;

  /// Per-source deadline.
  final Duration timeout;

  List<SourceSearchState> _results = const [];
  String _query = '';
  int _generation = 0;
  bool _disposed = false;

  /// One entry per source, in source order; empty before the first search.
  List<SourceSearchState> get results => _results;

  /// The query of the current search.
  String get query => _query;

  /// Starts a search for [query] (trimmed), superseding any running one.
  /// An empty query clears the results. Completes when every source settled.
  Future<void> search(String query) async {
    final generation = ++_generation;
    _query = query.trim();
    if (_query.isEmpty) {
      _results = const [];
      notifyListeners();
      return;
    }
    _results = [
      for (final s in _sources) SourceSearchState(s.ref, loading: true),
    ];
    notifyListeners();
    await Future.wait([
      for (var i = 0; i < _sources.length; i++) _searchOne(i, generation),
    ]);
  }

  Future<void> _searchOne(int index, int generation) async {
    final source = _sources[index];
    SourceSearchState next;
    try {
      final page = await source.search(_query, 1).timeout(timeout);
      next = SourceSearchState(source.ref, items: page.items);
    } on Object catch (e) {
      next = SourceSearchState(source.ref, error: e);
    }
    if (generation != _generation || _disposed) return;
    _results = [..._results]..[index] = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
