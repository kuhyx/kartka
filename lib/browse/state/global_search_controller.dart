import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kartka/core/models/manga.dart';
import 'package:kartka/core/models/source_ref.dart';
import 'package:kartka/core/source/manga_source.dart';

/// Page-1 search result of one source in a global search.
@immutable
class SourceSearchState {
  /// Creates a state; a fresh search starts with [loading] true.
  const new(
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
  new(List<MangaSource> sources, {this.timeout = const Duration(seconds: 20)})
    : _sources = List.unmodifiable(sources);

  List<MangaSource> _sources;

  /// Per-source deadline.
  final Duration timeout;

  final Map<String, SourceSearchState> _byId = {};
  String _query = '';
  int _generation = 0;
  bool _disposed = false;

  /// One entry per source, in source order; empty without a query.
  List<SourceSearchState> get results => [
    for (final s in _sources) ?_byId[s.ref.id],
  ];

  /// The query of the current search.
  String get query => _query;

  /// Starts a search for [query] (trimmed), superseding any running one.
  /// An empty query clears the results. Completes when every source settled.
  Future<void> search(String query) async {
    final generation = ++_generation;
    _query = query.trim();
    _byId.clear();
    if (_query.isEmpty) {
      notifyListeners();
      return;
    }
    await _searchAll(_sources, generation);
  }

  /// Switches to the live source list: removed sources drop out, added ones
  /// are searched with the current query, existing results are kept.
  Future<void> updateSources(List<MangaSource> sources) async {
    final known = {for (final s in _sources) s.ref.id};
    _sources = List.unmodifiable(sources);
    final ids = {for (final s in sources) s.ref.id};
    _byId.removeWhere((id, _) => !ids.contains(id));
    final added = [
      for (final s in sources)
        if (!known.contains(s.ref.id)) s,
    ];
    if (_query.isEmpty || added.isEmpty) {
      notifyListeners();
      return;
    }
    await _searchAll(added, _generation);
  }

  Future<void> _searchAll(List<MangaSource> sources, int generation) async {
    for (final s in sources) {
      _byId[s.ref.id] = SourceSearchState(s.ref, loading: true);
    }
    notifyListeners();
    await Future.wait([for (final s in sources) _searchOne(s, generation)]);
  }

  Future<void> _searchOne(MangaSource source, int generation) async {
    SourceSearchState next;
    try {
      final page = await source.search(_query, 1).timeout(timeout);
      next = SourceSearchState(source.ref, items: page.items);
    } on Object catch (e) {
      next = SourceSearchState(source.ref, error: e);
    }
    if (generation != _generation || _disposed) return;
    if (!_byId.containsKey(source.ref.id)) return; // Removed meanwhile.
    _byId[source.ref.id] = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
