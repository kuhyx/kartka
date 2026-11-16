/// The read/write surface the sync engine needs from RTDB, relative to the
/// `/kartka` root (DOCS-contracts §4, §12).
///
/// Path segments passed here are already RTDB-safe ([rtdbKey]); the engine
/// builds them, so implementations do not re-escape.
library;

import 'package:crdt_sync/crdt_sync.dart' show encodeKey;

/// Decoded-JSON access to the `/kartka` subtree.
abstract interface class RtdbTransport {
  /// The decoded JSON at [path], or null when absent.
  Future<Object?> get(String path);

  /// One atomic multi-path update: each key is a `/`-separated path relative
  /// to the root, each value replaces the node there (null deletes it).
  Future<void> patch(Map<String, Object?> updates);
}

/// Escapes [id] into one RTDB key segment: crdt_sync's `encodeKey` plus `/`,
/// which it leaves alone because it treats its input as a path.
String rtdbKey(String id) => encodeKey(id).replaceAll('/', '~2F');

/// Reverses [rtdbKey].
String rtdbKeyDecode(String key) => key
    .replaceAll('~2F', '/')
    .replaceAll('~2E', '.')
    .replaceAll('~24', r'$')
    .replaceAll('~23', '#')
    .replaceAll('~5B', '[')
    .replaceAll('~5D', ']')
    .replaceAll('~7E', '~');

/// An [RtdbTransport] over an in-memory JSON tree, with RTDB's semantics:
/// nulls and empty maps vanish, so a read never returns them.
class InMemoryRtdb implements RtdbTransport {
  /// Creates an empty database, or one holding [tree].
  new([Map<String, Object?>? tree]) : tree = tree ?? {};

  /// The whole stored tree; tests may inspect or seed it.
  final Map<String, Object?> tree;

  /// Number of [get] calls, so tests can assert polling stays cheap.
  int reads = 0;

  /// Number of [patch] calls.
  int writes = 0;

  /// When set, every call throws it (simulates being offline).
  Exception? failWith;

  @override
  Future<Object?> get(String path) async {
    reads++;
    _maybeFail();
    Object? node = tree;
    for (final segment in _segments(path)) {
      if (node is! Map<String, Object?>) return null;
      node = node[segment];
    }
    return _clone(node);
  }

  @override
  Future<void> patch(Map<String, Object?> updates) async {
    writes++;
    _maybeFail();
    updates.forEach(_set);
  }

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) throw failure;
  }

  void _set(String path, Object? value) {
    final segments = _segments(path);
    final parents = <Map<String, Object?>>[tree];
    var node = tree;
    for (final segment in segments.take(segments.length - 1)) {
      final child = node[segment];
      final next = child is Map<String, Object?> ? child : <String, Object?>{};
      node[segment] = next;
      node = next;
      parents.add(next);
    }
    final pruned = _prune(_clone(value));
    if (pruned == null) {
      node.remove(segments.last);
    } else {
      node[segments.last] = pruned;
    }
    // Drop maps the write left empty, as RTDB does.
    for (var i = parents.length - 1; i > 0; i--) {
      if (parents[i].isNotEmpty) break;
      parents[i - 1].remove(segments[i - 1]);
    }
  }

  static List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  static Object? _prune(Object? value) {
    if (value is! Map<String, Object?>) return value;
    final out = <String, Object?>{};
    value.forEach((k, v) {
      final p = _prune(v);
      if (p != null) out[k] = p;
    });
    return out.isEmpty ? null : out;
  }

  static Object? _clone(Object? value) => switch (value) {
    final Map<String, Object?> m => {
      for (final e in m.entries) e.key: _clone(e.value),
    },
    final List<Object?> l => l.map(_clone).toList(),
    _ => value,
  };
}
