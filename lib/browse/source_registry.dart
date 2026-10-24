import 'dart:async';

import 'package:kartka/app/feature.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';

/// Every [MangaSource] the registered features provide, as one live list.
///
/// Combines the static `KartkaFeature.sources` with every [SourceProvider]
/// stream (Suwayomi and plugin sources come and go at runtime). A provider
/// that has not emitted yet counts as empty, so one slow provider never
/// hides the others. Ids are unique: the first source with an id wins
/// (static sources first, then providers in registry order).
class SourceRegistry {
  /// Creates a registry and subscribes to every provider immediately.
  SourceRegistry({
    List<MangaSource> staticSources = const [],
    List<SourceProvider> providers = const [],
  }) : _static = List.unmodifiable(staticSources),
       _latest = List.filled(providers.length, const []) {
    for (final (i, p) in providers.indexed) {
      _subs.add(
        p.watch().listen((sources) {
          _latest[i] = sources;
          _publish();
        }, onError: (_) {}), // A failing provider keeps its last list.
      );
    }
    _publish();
  }

  /// Builds the registry from every feature in [registry].
  factory SourceRegistry.fromRegistry(KartkaRegistry registry) =>
      SourceRegistry(
        staticSources: registry.sources,
        providers: registry.all<SourceProvider>(),
      );

  final List<MangaSource> _static;
  final List<List<MangaSource>> _latest;
  final List<StreamSubscription<List<MangaSource>>> _subs = [];
  final _changes = StreamController<List<MangaSource>>.broadcast(sync: true);
  List<MangaSource> _current = const [];
  Map<String, MangaSource> _byId = const {};

  /// The current sources, deduplicated by id.
  List<MangaSource> get current => _current;

  /// The source with [id], or null when none is registered right now.
  MangaSource? byId(String id) => _byId[id];

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

  void _publish() {
    final byId = <String, MangaSource>{};
    for (final s in [_static, ..._latest].expand((l) => l)) {
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
