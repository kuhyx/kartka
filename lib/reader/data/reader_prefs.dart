import 'dart:convert';

import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';

/// Reader preferences in the device-local key-value store.
class ReaderPrefs {
  /// Prefs stored in the given key-value store.
  const new(this._kv);

  final KeyValueStore _kv;

  /// Key of the global settings JSON.
  static const settingsKey = 'reader.settings';

  /// Prefix of per-manga mode keys; the manga key is hashed so URLs never
  /// end up in store keys.
  static const modePrefix = 'reader.mode.';

  /// The global settings, defaults when missing or unreadable.
  Future<ReaderSettings> settings() async {
    final raw = await _kv.get(settingsKey);
    if (raw == null) return const ReaderSettings();
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) return ReaderSettings.fromJson(json);
    } on FormatException {
      // Fall through: a corrupt value must not lock the reader.
    }
    return const ReaderSettings();
  }

  /// Stores the global settings.
  Future<void> saveSettings(ReaderSettings s) =>
      _kv.set(settingsKey, jsonEncode(s.toJson()));

  /// The mode chosen for [key], or null to use the default.
  Future<ReaderMode?> modeFor(MangaKey key) async =>
      ReaderMode.fromId(await _kv.get(_modeKey(key)));

  /// Sets the mode for [key]; null clears the override.
  Future<void> setModeFor(MangaKey key, ReaderMode? mode) => mode == null
      ? _kv.remove(_modeKey(key))
      : _kv.set(_modeKey(key), mode.id);

  /// The mode [key] opens in: its override, else the global default.
  Future<ReaderMode> effectiveMode(MangaKey key) async =>
      await modeFor(key) ?? (await settings()).defaultMode;

  String _modeKey(MangaKey key) => '$modePrefix${mangaKeyHash(key)}';
}
