/// Read-only access to Kartka's Firebase RTDB tree for parts that only
/// consume synced data (e.g. `source_health` reading `source_health/`).
///
/// Paths are relative to the `/kartka` root and `/`-separated, for example
/// `source_health` or `source_health/<sourceIdHash>`. Values are decoded JSON
/// exactly as stored: `Map<String, Object?>`, `List<Object?>`, `String`,
/// `num`, `bool`, or `null` when nothing is stored at the path.
///
/// The sync part owns the real (network) implementation; consumers depend on
/// this interface only and use [InMemoryRtdbReader] in tests.
library;

import 'dart:async';

/// Reads decoded JSON from the `/kartka` RTDB root. Never writes.
abstract interface class RtdbReader {
  /// The value at [path], or null when absent.
  ///
  /// Throws a `RemoteSyncError` subtype when the database cannot be reached
  /// or rejects the read; a missing path is a benign null, never an error.
  Future<Object?> get(String path);

  /// Emits the value at [path] now and again whenever it changes.
  ///
  /// Real implementations poll; the stream never emits two equal values in a
  /// row. Cancel the subscription to stop polling.
  Stream<Object?> watch(String path);
}

/// An [RtdbReader] over a fixed in-memory tree, for tests and offline mode.
class InMemoryRtdbReader implements RtdbReader {
  /// Creates a reader over [tree] (the decoded JSON under `/kartka`).
  new([Map<String, Object?>? tree]) : _tree = tree ?? <String, Object?>{};

  Map<String, Object?> _tree;
  final _changes = StreamController<void>.broadcast();

  /// Replaces the whole tree and notifies every [watch] subscriber.
  void replace(Map<String, Object?> value) {
    _tree = value;
    _changes.add(null);
  }

  @override
  Future<Object?> get(String path) async => _lookup(path);

  @override
  Stream<Object?> watch(String path) async* {
    var last = _lookup(path);
    yield last;
    await for (final _ in _changes.stream) {
      final next = _lookup(path);
      if (_jsonEquals(next, last)) continue;
      last = next;
      yield next;
    }
  }

  Object? _lookup(String path) {
    Object? node = _tree;
    for (final segment in path.split('/').where((s) => s.isNotEmpty)) {
      if (node is! Map<String, Object?>) return null;
      node = node[segment];
    }
    return node;
  }
}

/// Deep structural equality over decoded JSON values.
bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
