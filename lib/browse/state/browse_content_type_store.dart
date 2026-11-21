import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/platform/key_value_store.dart';

/// Which content types Browse lists (synced setting `browse.contentType`,
/// a JSON list of `ContentType` names; an old single choice still reads,
/// see [ContentTypes.parse]). Unset or unknown means every type ticked.
/// Every source screen and the global search follow it.
///
/// [toggle] waits for [ready], so a quick first tap never races the stored
/// value.
class BrowseContentTypeStore extends ValueNotifier<ContentTypes> {
  /// Loads from the store (null: in memory only), reloading when [reloadOn]
  /// names [storageKey] (a peer's change).
  new(this._kv, {Stream<String>? reloadOn}) : super(ContentTypes.all) {
    ready = _load();
    reloadOn?.where((k) => k == storageKey).listen((_) => _load());
  }

  /// Synced setting key.
  static const storageKey = 'browse.contentType';

  final KeyValueStore? _kv;

  /// Completes once the stored value is read.
  late final Future<void> ready;

  Future<void> _load() async {
    value = ContentTypes.parse(await _kv?.get(storageKey)) ?? ContentTypes.all;
  }

  /// Ticks or unticks [type] and stores the ticked list.
  Future<void> toggle(ContentType type) async {
    await ready;
    value = value.toggled(type);
    await _kv?.set(storageKey, jsonEncode(value.toJson()));
  }
}
