import 'package:flutter/foundation.dart';
import 'package:kartka/platform/key_value_store.dart';

/// The manga detail screen's "Unread first" chapter sort, one setting for
/// every manga (`browse.unreadFirst`, `'true'` / `'false'`). Off means the
/// plain newest-first list.
///
/// The value is false until [ready]; [set] waits for it, so a quick first
/// toggle never races the stored value.
class ChapterSortStore extends ValueNotifier<bool> {
  /// Creates the store and starts loading from [_kv] (null: kept in memory
  /// only). [reloadOn] carries synced keys a peer changed.
  new(this._kv, {Stream<String>? reloadOn}) : super(false) {
    ready = _load();
    reloadOn?.where((k) => k == storageKey).listen((_) => _load());
  }

  /// KeyValueStore key holding the choice.
  static const storageKey = 'browse.unreadFirst';

  final KeyValueStore? _kv;

  /// Completes once the saved choice (if any) is in [value].
  late final Future<void> ready;

  Future<void> _load() async {
    value = await _kv?.get(storageKey) == 'true';
  }

  /// Switches "Unread first" on or off and persists it.
  Future<void> set({required bool unreadFirst}) async {
    await ready;
    value = unreadFirst;
    await _kv?.set(storageKey, '$unreadFirst');
  }
}
