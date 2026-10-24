import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';

/// Current MangaDex settings, persisted as JSON in a [KeyValueStore].
///
/// Starts on [MangadexSettings.defaults] and loads the saved value once;
/// readers that need the saved value await `ready` first.
class MangadexSettingsStore extends ValueNotifier<MangadexSettings> {
  /// Creates the store and starts loading from the given [KeyValueStore].
  /// [reloadOn] carries synced keys a peer changed; [storageKey] reloads.
  new(this._kv, {Stream<String>? reloadOn}) : super(MangadexSettings.defaults) {
    ready = _load();
    reloadOn?.where((k) => k == storageKey).listen((_) => _load());
  }

  /// KeyValueStore key holding the JSON.
  static const storageKey = 'mangadex.settings';

  final KeyValueStore _kv;

  /// Completes once the saved settings (if any) are in [value].
  late final Future<void> ready;

  Future<void> _load() async {
    final raw = await _kv.get(storageKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        value = MangadexSettings.fromJson(json);
      }
    } on FormatException {
      // A corrupt value keeps the defaults; the next save overwrites it.
    }
  }

  /// Applies and persists [settings].
  Future<void> save(MangadexSettings settings) async {
    await ready;
    value = settings;
    await _kv.set(storageKey, jsonEncode(settings.toJson()));
  }
}
