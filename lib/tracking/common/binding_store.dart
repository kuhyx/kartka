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
class KvBindingStore implements BindingStore {
  /// Creates the store over [_kv].
  new(this._kv);

  static const _prefix = 'tracking.binding.';

  final KeyValueStore _kv;
  final StreamController<MangaKey> _changes = StreamController.broadcast();

  String _slot(MangaKey key, String service) =>
      '$_prefix${mangaKeyHash(key)}.$service';

  @override
  Future<List<TrackBinding>> all() async {
    final entries = await _kv.entries(prefix: _prefix);
    return [for (final raw in entries.values) ?_decode(raw)];
  }

  @override
  Stream<List<TrackBinding>> watch(MangaKey key) {
    // One tick for the initial read, one per change; asyncMap keeps order.
    StreamSubscription<MangaKey>? sub;
    final ticks = StreamController<void>();
    ticks
      ..onListen = () {
        ticks.add(null);
        sub = _changes.stream
            .where((k) => k == key)
            .listen((_) => ticks.add(null));
      }
      ..onCancel = () => sub?.cancel();
    return ticks.stream.asyncMap((_) => _of(key));
  }

  @override
  Future<void> put(TrackBinding binding) async {
    final slot = _slot(binding.key, binding.service);
    final old = _decode(await _kv.get(slot));
    var merged = binding;
    if (old != null && old.remoteId == binding.remoteId) {
      final a = old.lastPushedChapter;
      final b = binding.lastPushedChapter;
      merged = binding.copyWith(
        lastPushedChapter: a == null || b == null ? a ?? b : math.max(a, b),
      );
    }
    await _kv.set(slot, jsonEncode(merged.toJson()));
    _changes.add(binding.key);
  }

  @override
  Future<void> remove(MangaKey key, String service) async {
    await _kv.remove(_slot(key, service));
    _changes.add(key);
  }

  Future<List<TrackBinding>> _of(MangaKey key) async =>
      (await all()).where((b) => b.key == key).toList();

  static TrackBinding? _decode(String? raw) {
    if (raw == null) return null;
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
