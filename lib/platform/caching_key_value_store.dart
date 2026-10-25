import 'dart:async';

import 'package:kartka/platform/key_value_store.dart';

/// Read-through, per-launch in-memory cache over a [KeyValueStore]
/// (`KartkaPlatform.secrets`, contracts-runtime §13).
///
/// Every reader asks for a key on each use (`AniListAuth.token()` runs on
/// every tracked progress push), and on web each read is a wrapper round
/// trip. A key, present or absent, is read from the backend once; this
/// store's own [set] / [remove] keep the cache current. Writes made behind
/// its back (hand-editing `~/.config/kartka/secrets.json`) show after a
/// restart.
///
/// The cache holds the read's [Future], so a burst of concurrent reads of a
/// key costs one backend call. A failed read or write is never cached: the
/// next read goes back to the backend. Values never leave this object.
class CachingKeyValueStore implements KeyValueStore {
  /// Wraps the store that actually holds the values.
  new(this._inner);

  final KeyValueStore _inner;
  final Map<String, Future<String?>> _cache = {};

  @override
  Future<String?> get(String key) {
    final cached = _cache[key];
    if (cached != null) return cached;
    final read = _inner.get(key);
    _cache[key] = read;
    // Drop a failed read, unless a write already replaced it. The caller
    // still sees the error through `read` itself.
    unawaited(
      read.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_cache[key], read)) _forget(key);
        },
      ),
    );
    return read;
  }

  @override
  Future<void> set(String key, String value) =>
      _write(key, () => _inner.set(key, value), value);

  @override
  Future<void> remove(String key) =>
      _write(key, () => _inner.remove(key), null);

  /// Runs [write], then caches [result]; on failure forgets [key] so the
  /// next read asks the backend what actually landed.
  Future<void> _write(
    String key,
    Future<void> Function() write,
    String? result,
  ) async {
    try {
      await write();
    } on Object {
      _forget(key);
      rethrow;
    }
    _cache[key] = Future.value(result);
  }

  // The dropped future already has its listeners; nothing awaits it here.
  void _forget(String key) => unawaited(_cache.remove(key));

  @override
  Future<Map<String, String>> entries({String prefix = ''}) =>
      _inner.entries(prefix: prefix);
}
