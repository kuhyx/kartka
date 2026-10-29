import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  Future<Map<String, T>>? _rows;
  Map<String, T>? _snapshot;
  Future<void> _tail = Future.value();

  /// All rows keyed by id (the store key minus the prefix), loaded once.
  Future<Map<String, T>> load() => _rows ??= _read();

  Future<Map<String, T>> _read() async {
    final raw = await _store.entries(prefix: _prefix);
    final job = (raw: raw, cut: _prefix.length, decode: _decode);
    final total = raw.values.fold(0, (n, v) => n + v.length);
    // Every row of the table at once, at startup: big tables (read marks,
    // the library) are decoded off the UI isolate.
    return total < kvTableOffUiChars
        ? _decodeRows(job)
        : await compute(_decodeRows<T>, job);
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
  Future<T?> get(String id) async => (await load())[id];

  /// Stores [value] as row [id].
  Future<void> put(String id, T value) => update(id, (_) => value);

  /// Replaces row [id] with `change(current)`; a `null` result or an equal
  /// value leaves the row (and the store) untouched.
  Future<void> update(String id, T? Function(T? current) change) {
    final done = _tail.then((_) => _apply(id, change));
    _tail = done.catchError((Object _) {});
    return done;
  }

  Future<void> _apply(String id, T? Function(T?) change) async {
    final rows = await load();
    final current = rows[id];
    final next = change(current);
    if (next == null || next == current) return;
    await _store.set('$_prefix$id', jsonEncode(_encode(next)));
    rows[id] = next;
    _changes.add(_snapshot = Map.unmodifiable(rows));
  }

  /// Emits an immutable snapshot on listen, then one after every change.
  Stream<Map<String, T>> watch() {
    late final StreamController<Map<String, T>> out;
    StreamSubscription<Map<String, T>>? sub;
    out = StreamController<Map<String, T>>(
      onListen: () async {
        sub = _changes.stream.listen(out.add);
        // One shared snapshot: N per-entry watchers must not copy N times.
        final rows = await load();
        out.add(_snapshot ??= Map.unmodifiable(rows));
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }
}
