import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kartka/library/data/row_watchers.dart';
import 'package:kartka/platform/key_value_store.dart';

/// Tables whose stored rows total at least this many chars are decoded in
/// a background isolate.
const int kvTableOffUiChars = 64 * 1024;

typedef _RowsJob<T> = ({
  Map<String, String> raw,
  int cut,
  T Function(Map<String, Object?>) decode,
});

/// One JSON record per [KeyValueStore] key under a prefix, cached in memory
/// and observable.
///
/// `decode` must be sendable to an isolate (a top-level or static function,
/// or a constructor tear-off), since large tables are decoded off the UI.
///
/// Writes are serialised, so a read-modify-write in [update] cannot lose a
/// concurrent write; that is what lets the repositories apply LWW and
/// "never decreases" against the true current value.
class KvTable<T> {
  /// Creates a table over `store` for keys starting with `prefix`.
  new(
    this._store,
    this._prefix, {
    required this._decode,
    required this._encode,
  });

  final KeyValueStore _store;
  final String _prefix;
  final T Function(Map<String, Object?>) _decode;
  final Map<String, Object?> Function(T) _encode;
  final _changes = StreamController<Map<String, T>>.broadcast(sync: true);
  final _rowWatchers = RowWatchers<T>();
  Future<void>? _ready;
  // The rows. A snapshot handed out is a read-only view of this very map,
  // so a write first replaces it with a copy (only if one was handed out
  // since the last write): a burst of writes copies once, not per row.
  Map<String, T> _live = {};
  Map<String, T>? _snapshot;
  Future<void> _tail = Future.value();
  int _queued = 0;
  bool _dirty = false;

  /// Live-map copies made so far (the cost tests bound them).
  @visibleForTesting
  int copies = 0;

  /// Entries those copies moved.
  @visibleForTesting
  int rowsCopied = 0;

  /// Row-watcher callbacks run so far.
  @visibleForTesting
  int get rowCallbacks => _rowWatchers.callbacks;

  Future<void> _load() => _ready ??= _read();

  /// All rows keyed by id (the store key minus the prefix), loaded once: an
  /// immutable snapshot, never changed by later writes.
  Future<Map<String, T>> load() async {
    await _load();
    return _publish();
  }

  Future<void> _read() async {
    final raw = await _store.entries(prefix: _prefix);
    final job = (raw: raw, cut: _prefix.length, decode: _decode);
    final total = raw.values.fold(0, (n, v) => n + v.length);
    // Every row of the table at once, at startup: big tables (read marks,
    // the library) are decoded off the UI isolate.
    _live = total < kvTableOffUiChars
        ? _decodeRows(job)
        : await compute(_decodeRows<T>, job);
  }

  Map<String, T> _publish() => _snapshot ??= UnmodifiableMapView(_live);

  Map<String, T> _writable() {
    if (_snapshot != null) {
      copies++;
      rowsCopied += _live.length;
      _live = Map.of(_live);
      _snapshot = null;
    }
    return _live;
  }

  static Map<String, T> _decodeRows<T>(_RowsJob<T> job) => {
    for (final MapEntry(:key, :value) in job.raw.entries)
      key.substring(job.cut): ?_tryDecode(value, job.decode),
  };

  static T? _tryDecode<T>(String value, T Function(Map<String, Object?>) f) {
    try {
      final json = jsonDecode(value);
      return json is Map<String, Object?> ? f(json) : null;
    } on Object {
      // A corrupt or foreign row must not take the whole library down.
      return null;
    }
  }

  /// The row [id], or `null`.
  Future<T?> get(String id) async {
    await _load();
    return _live[id];
  }

  /// Stores [value] as row [id].
  Future<void> put(String id, T value) => update(id, (_) => value);

  /// Stores every row of [values]: one burst, so watchers of the table hear
  /// it once (see [updateAll]).
  Future<void> putAll(Map<String, T> values) =>
      updateAll({for (final e in values.entries) e.key: (_) => e.value});

  /// Replaces row [id] with `change(current)`; a `null` result or an equal
  /// value leaves the row (and the store) untouched.
  Future<void> update(String id, T? Function(T? current) change) {
    // Counted now, not when it runs: the table's watchers hear one emission
    // after the whole queue drains, so writes issued back to back (a sync
    // pull replaying N rows) cost one snapshot, not N.
    _queued++;
    final done = _tail.then((_) => _apply(id, change));
    _tail = done.catchError((Object _) {});
    return done;
  }

  /// [update] of every row in [changes], applied in order as one burst.
  Future<void> updateAll(Map<String, T? Function(T? current)> changes) =>
      Future.wait([
        for (final MapEntry(:key, :value) in changes.entries)
          update(key, value),
      ]);

  Future<void> _apply(String id, T? Function(T?) change) async {
    try {
      await _load();
      final current = _live[id];
      final next = change(current);
      if (next == null || next == current) return;
      await _store.set('$_prefix$id', jsonEncode(_encode(next)));
      _writable()[id] = next;
      _dirty = true;
      _rowWatchers.changed(id, next);
    } finally {
      if (--_queued == 0 && _dirty) {
        _dirty = false;
        // Nobody listening: no snapshot, so the next write copies nothing.
        if (_changes.hasListener) _changes.add(_publish());
      }
    }
  }

  /// Row [id] on listen (`null` when absent), then after each change of
  /// that row only.
  Stream<T?> watchRow(String id) =>
      _rowWatchers.watch(id, _load(), () => _live[id]);

  /// Emits an immutable snapshot on listen, then one after every change
  /// (or burst of changes).
  Stream<Map<String, T>> watch() {
    late final StreamController<Map<String, T>> out;
    StreamSubscription<Map<String, T>>? sub;
    out = StreamController<Map<String, T>>(
      sync: true,
      onListen: () async {
        sub = _changes.stream.listen(out.add);
        // One shared snapshot: N per-entry watchers must not copy N times.
        await _load();
        out.add(_publish());
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }
}
