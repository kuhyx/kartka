import 'package:kartka/platform/key_value_store.dart';

/// Key prefixes read after the library's keys on Android: the sync
/// engine's mirror (`sync.`, ~7 MB of read-mark buckets) and the stored
/// chapter lists (`browse.chapters.`, ~5 MB). Together they were 13 of the
/// 20 MB the phone parsed before its first library paint (library.load
/// a133bbb8); nothing on that paint reads them.
const kvDeferredPrefixes = ['sync.', 'browse.chapters.'];

/// A [KeyValueStore] over two: keys under [deferredPrefixes] live in
/// [deferred], every other key in [fast].
///
/// [deferred] is touched only once [fast] has answered, so its read never
/// competes with the one the library waits on. Keys written before the
/// split still sit in [fast] until [migrate] moves them: a deferred key is
/// read from [deferred] first, then [fast]; it is written to [deferred]
/// only and removed from both, so an old copy cannot come back.
class SplitKeyValueStore implements OffUiDecodingStore {
  /// Splits by [deferredPrefixes]; [flushFast] / [flushDeferred] write a
  /// store's pending changes now (migration order, `flushOnBackground`).
  new(
    this.fast,
    this.deferred, {
    required this.deferredPrefixes,
    this.flushFast,
    this.flushDeferred,
  });

  /// Holds every key not under [deferredPrefixes].
  final KeyValueStore fast;

  /// Holds the keys under [deferredPrefixes].
  final KeyValueStore deferred;

  /// Prefixes of the keys kept in [deferred].
  final List<String> deferredPrefixes;

  /// Writes [fast]'s pending changes, if it buffers any.
  final Future<void> Function()? flushFast;

  /// Writes [deferred]'s pending changes, if it buffers any.
  final Future<void> Function()? flushDeferred;

  // Any answer (or failure) of the fast store means its read is over.
  late final Future<void> _fastRead = fast
      .get('')
      .then((_) {}, onError: (_) {});

  /// Whether [key] lives in [deferred].
  bool isDeferred(String key) => deferredPrefixes.any(key.startsWith);

  bool _reachesDeferred(String prefix) =>
      deferredPrefixes.any((p) => p.startsWith(prefix) || prefix.startsWith(p));

  Future<KeyValueStore> _late() async {
    await _fastRead;
    return deferred;
  }

  @override
  Future<String?> get(String key) async {
    if (!isDeferred(key)) return await fast.get(key);
    return await (await _late()).get(key) ?? await fast.get(key);
  }

  @override
  Future<void> set(String key, String value) async {
    if (!isDeferred(key)) return await fast.set(key, value);
    await (await _late()).set(key, value);
  }

  @override
  Future<void> remove(String key) async {
    if (isDeferred(key)) await (await _late()).remove(key);
    await fast.remove(key);
  }

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async {
    final own = await fast.entries(prefix: prefix);
    if (!_reachesDeferred(prefix)) return own;
    return {...own, ...await (await _late()).entries(prefix: prefix)};
  }

  @override
  Future<List<R?>> decodeAll<R extends Object>(
    List<String> keys,
    R? Function(String text) decode,
  ) async {
    final late = [
      for (final k in keys)
        if (isDeferred(k)) k,
    ];
    final fromLate = late.isEmpty
        ? const <Object?>[]
        : await _decode(await _late(), late, decode);
    final byKey = {for (var i = 0; i < late.length; i++) late[i]: fromLate[i]};
    // The fast store answers its own keys and any deferred key not moved
    // over yet.
    final rest = [
      for (final k in keys)
        if (byKey[k] == null) k,
    ];
    final fromFast = await _decode(fast, rest, decode);
    for (var i = 0; i < rest.length; i++) {
      byKey[rest[i]] = fromFast[i];
    }
    return [for (final k in keys) byKey[k] as R?];
  }

  static Future<List<R?>> _decode<R extends Object>(
    KeyValueStore store,
    List<String> keys,
    R? Function(String text) decode,
  ) async {
    if (keys.isEmpty) return const [];
    if (store is OffUiDecodingStore) return await store.decodeAll(keys, decode);
    return [
      for (final k in keys)
        if (await store.get(k) case final text?) decode(text) else null,
    ];
  }

  /// Writes both stores' pending changes now.
  Future<void> flush() async {
    await flushFast?.call();
    await flushDeferred?.call();
  }

  /// Moves deferred keys still in [fast] over: copies each one [deferred]
  /// lacks (a newer write there wins), flushes [deferred], and only then
  /// removes them from [fast] and flushes it. Cut short at any point, the
  /// next run finishes it without losing a value.
  Future<void> migrate() async {
    final moved = {
      for (final p in deferredPrefixes) ...await fast.entries(prefix: p),
    };
    if (moved.isEmpty) return;
    final late = await _late();
    for (final MapEntry(:key, :value) in moved.entries) {
      if (await late.get(key) == null) await late.set(key, value);
    }
    await flushDeferred?.call();
    for (final key in moved.keys) {
      await fast.remove(key);
    }
    await flushFast?.call();
  }
}
