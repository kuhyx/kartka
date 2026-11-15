import 'package:flutter/foundation.dart';
import 'package:kartka/platform/key_value_store.dart';

/// Which language chip the Browse grid shows (`browse.shown`, a
/// language bucket); null means the "All" chip. Kept per device: the chip
/// is where this screen was left, not a synced preference.
///
/// The value is null (All) until [ready]; [set] waits for it, so a quick
/// first tap never races the stored value.
class BrowseShownStore extends ValueNotifier<String?> {
  /// Creates the store and starts loading from [_kv] (null: kept in memory
  /// only).
  new(this._kv) : super(null) {
    ready = _load();
  }

  /// KeyValueStore key holding the bucket; absent means All.
  static const storageKey = 'browse.shown';

  final KeyValueStore? _kv;

  /// Completes once the saved choice (if any) is in [value].
  late final Future<void> ready;

  Future<void> _load() async {
    value = await _kv?.get(storageKey);
  }

  /// Shows [bucket] (null: All) and persists it.
  Future<void> set(String? bucket) async {
    await ready;
    value = bucket;
    final kv = _kv;
    if (kv == null) return;
    await (bucket == null ? kv.remove(storageKey) : kv.set(storageKey, bucket));
  }
}
