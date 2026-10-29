import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/tracking/common/track_binding.dart';

/// Where [TrackBinding]s live. Sync may wrap it via [BindingStoreDecorator].
abstract interface class BindingStore {
  /// Every binding.
  Future<List<TrackBinding>> all();

  /// Bindings of [key]: the current list first, then one per change.
  Stream<List<TrackBinding>> watch(MangaKey key);

  /// Stores [binding]. For the same remote id, `lastPushedChapter` never
  /// goes down; binding a different remote id replaces the entry.
  Future<void> put(TrackBinding binding);

  /// Drops the [service] binding of [key].
  Future<void> remove(MangaKey key, String service);
}

/// Port for sync to decorate the binding store (supplied through
/// `KartkaFeature.services`, applied in registry order).
abstract interface class BindingStoreDecorator {
  /// Wraps [inner].
  BindingStore decorate(BindingStore inner);
}

/// [BindingStore] over a [KeyValueStore] (`tracking.binding.<hash>.<svc>`).
///
/// Every binding is read from the store once, then served from memory:
/// the library watches each of its manga, and a full scan + decode per
/// watcher was N² at cold start. Safe because every write goes through
/// [put] / [remove] (sync and .tachibk import included) and the app builds
/// one store per key-value store (tracking_feature.dart).
class KvBindingStore implements BindingStore {
  /// Creates the store over [_kv].
  new(this._kv);

  static const _prefix = 'tracking.binding.';

  final KeyValueStore _kv;
  // Per key, so a change re-reads only that key's watchers.
  final _watchers = <MangaKey, Set<StreamController<void>>>{};
  late final Future<Map<MangaKey, Map<String, TrackBinding>>> _index = _load();

  Future<Map<MangaKey, Map<String, TrackBinding>>> _load() async {
    final index = <MangaKey, Map<String, TrackBinding>>{};
    for (final raw in (await _kv.entries(prefix: _prefix)).values) {
      final b = _decode(raw);
      if (b != null) (index[b.key] ??= {})[b.service] = b;
    }
    return index;
  }

  String _slot(MangaKey key, String service) =>
      '$_prefix${mangaKeyHash(key)}.$service';

  @override
  Future<List<TrackBinding>> all() async => [
    for (final byService in (await _index).values) ...byService.values,
  ];

  @override
  Stream<List<TrackBinding>> watch(MangaKey key) {
    // One tick for the initial read, one per change; asyncMap keeps order.
    final ticks = StreamController<void>();
    ticks
      ..onListen = () {
        ticks.add(null);
        (_watchers[key] ??= {}).add(ticks);
      }
      ..onCancel = () {
        final set = _watchers[key]?..remove(ticks);
        if (set != null && set.isEmpty) _watchers.remove(key);
      };
    return ticks.stream.asyncMap((_) => _of(key));
  }

  void _changed(MangaKey key) {
    for (final ticks in [...?_watchers[key]]) {
      ticks.add(null);
    }
  }

  @override
  Future<void> put(TrackBinding binding) async {
    final index = await _index;
    final old = index[binding.key]?[binding.service];
    var merged = binding;
    if (old != null && old.remoteId == binding.remoteId) {
      final a = old.lastPushedChapter;
      final b = binding.lastPushedChapter;
      merged = binding.copyWith(
        lastPushedChapter: a == null || b == null ? a ?? b : math.max(a, b),
      );
    }
    await _kv.set(
      _slot(binding.key, binding.service),
      jsonEncode(merged.toJson()),
    );
    (index[binding.key] ??= {})[binding.service] = merged;
    _changed(binding.key);
  }

  @override
  Future<void> remove(MangaKey key, String service) async {
    final index = await _index;
    await _kv.remove(_slot(key, service));
    final byService = index[key]?..remove(service);
    if (byService != null && byService.isEmpty) index.remove(key);
    _changed(key);
  }

  Future<List<TrackBinding>> _of(MangaKey key) async => [
    ...?(await _index)[key]?.values,
  ];

  static TrackBinding? _decode(String raw) {
    try {
      return TrackBinding.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }
}

/// [BindingStore] that wraps [_base] with every [BindingStoreDecorator] on
/// first use: the registry is complete only after every feature factory ran.
class LazyBindingStore implements BindingStore {
  /// Creates the store; [_decorators] is read once, lazily.
  new(this._base, this._decorators);

  final BindingStore _base;
  final List<BindingStoreDecorator> Function() _decorators;

  late final BindingStore _store = _decorators().fold(
    _base,
    (inner, d) => d.decorate(inner),
  );

  @override
  Future<List<TrackBinding>> all() => _store.all();

  @override
  Stream<List<TrackBinding>> watch(MangaKey key) => _store.watch(key);

  @override
  Future<void> put(TrackBinding binding) => _store.put(binding);

  @override
  Future<void> remove(MangaKey key, String service) =>
      _store.remove(key, service);
}
