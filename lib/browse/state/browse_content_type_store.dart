import 'package:flutter/foundation.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/platform/key_value_store.dart';

/// Which content types Browse lists (synced setting `browse.contentType`,
/// a [ContentType] name). Unset or unknown means [ContentType.manga]: kuhy
/// reads manga. Every source screen and the global search follow it.
///
/// [cycle] waits for [ready], so a quick first tap never races the stored
/// value.
class BrowseContentTypeStore extends ValueNotifier<ContentType> {
  /// Creates the store and starts loading from [_kv] (null: kept in memory
  /// only). [reloadOn] carries synced keys a peer changed; [storageKey]
  /// reloads.
  new(this._kv, {Stream<String>? reloadOn}) : super(ContentType.manga) {
    ready = _load();
    reloadOn?.where((k) => k == storageKey).listen((_) => _load());
  }

  /// KeyValueStore key holding the name.
  static const storageKey = 'browse.contentType';

  final KeyValueStore? _kv;

  /// Completes once the saved choice (if any) is in [value].
  late final Future<void> ready;

  Future<void> _load() async {
    value =
        ContentType.tryParse(await _kv?.get(storageKey)) ?? ContentType.manga;
  }

  /// Moves to the next state of the toggle and persists it.
  Future<void> cycle() async {
    await ready;
    value = value.next;
    await _kv?.set(storageKey, value.name);
  }
}
