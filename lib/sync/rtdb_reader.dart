/// Read-only access to Kartka's Firebase RTDB tree for parts that only
/// consume synced data (e.g. `source_health` reading `source_health/`).
///
/// Paths are relative to the `/kartka-e2e` root and `/`-separated, for example
/// `source_health` or `source_health/<sourceIdHash>`. Values are decoded JSON
/// exactly as stored: `Map<String, Object?>`, `List<Object?>`, `String`,
/// `num`, `bool`, or `null` when nothing is stored at the path.
///
/// The sync part owns the real (network) implementation; consumers depend on
/// this interface only and use [InMemoryRtdbReader] in tests.
library;

import 'dart:async';

import 'package:kartka/sync/merge/merge_rules.dart' show canon;

/// Reads decoded JSON from the `/kartka-e2e` RTDB root. Never writes.
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
  /// Creates a reader over [tree] (the decoded JSON under `/kartka-e2e`).
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
  Stream<Object?> watch(String path) {
    // A plain controller, not `async*`: cancelling an async* generator
    // parked in `await for` on a silent stream never completes.
    StreamSubscription<void>? sub;
    String? last;
    late final StreamController<Object?> out;
    void emit() {
      final value = _lookup(path);
      final text = canon(value);
      if (text == last) return;
      last = text;
      out.add(value);
    }

    out = StreamController<Object?>(
      onListen: () {
        emit();
        sub = _changes.stream.listen((_) => emit());
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
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
