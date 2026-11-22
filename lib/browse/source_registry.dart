import 'dart:async';

import 'package:kartka/app/feature.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';

/// Every [MangaSource] the registered features provide, as one live list.
///
/// Merges every [SourceProvider] stream (Suwayomi and plugin sources come
/// and go at runtime). A provider that has not emitted yet counts as empty,
/// so one slow provider never hides the others. Ids are unique: the first
/// source with an id wins, providers taken in registry order. [settled]
/// says whether a missing id is known to be missing.
class SourceRegistry {
  /// Creates a registry and subscribes to every provider immediately.
  new(List<SourceProvider> providers)
    : _providers = List.unmodifiable(providers),
      _latest = List.filled(providers.length, null) {
    for (final (i, p) in providers.indexed) {
      _subs.add(
        p.watch().listen((sources) {
          _latest[i] = sources;
          _relisting.remove(i);
          _publish();
        }, onError: (_) {}), // A failing provider keeps its last list.
      );
    }
    _publish();
  }

  /// Builds the registry from every feature in [registry].
  factory fromRegistry(KartkaRegistry registry) =>
      SourceRegistry(registry.all<SourceProvider>());

  final List<SourceProvider> _providers;
  final List<List<MangaSource>?> _latest; // null: not listed yet
  final _relisting = <int>{};
  final List<StreamSubscription<List<MangaSource>>> _subs = [];
  final _changes = StreamController<List<MangaSource>>.broadcast(sync: true);
  List<MangaSource> _current = const [];
  Map<String, MangaSource> _byId = const {};

  /// The current sources, deduplicated by id.
  List<MangaSource> get current => _current;

  /// The source with [id], or null when none is registered right now.
  MangaSource? byId(String id) => _byId[id];

  /// Whether every provider has listed and none is re-listing: an id
  /// missing now is missing, not just late.
  bool get settled => _relisting.isEmpty && !_latest.contains(null);

  /// The current list, then every change.
  Stream<List<MangaSource>> watch() {
    late StreamController<List<MangaSource>> out;
    StreamSubscription<List<MangaSource>>? sub;
    out = StreamController<List<MangaSource>>(
      onListen: () {
        out.add(_current);
        sub = _changes.stream.listen(out.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// Asks every [RefreshableSourceProvider] to re-list its sources; their
  /// new lists arrive through [watch], and each one is unsettled until
  /// its new list does. A failing provider is ignored.
  Future<void> refresh() => Future.wait([
    for (final (i, p) in _providers.indexed)
      if (p is RefreshableSourceProvider) _relist(i, p),
  ]);

  Future<void> _relist(int i, RefreshableSourceProvider p) {
    _relisting.add(i);
    return p.refresh().catchError((Object _) {
      if (_relisting.remove(i)) _publish();
    });
  }

  void _publish() {
    final byId = <String, MangaSource>{};
    for (final s in _latest.expand((l) => l ?? const <MangaSource>[])) {
      byId.putIfAbsent(s.ref.id, () => s);
    }
    _byId = Map.unmodifiable(byId);
    _current = List.unmodifiable(byId.values);
    _changes.add(_current);
  }

  /// Cancels every provider subscription.
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _changes.close();
  }
}
