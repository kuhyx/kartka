import 'dart:convert';

import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

/// A plugin kept in the [KeyValueStore].
class InstalledPlugin {
  /// Creates a record.
  const new({
    required this.manifest,
    required this.source,
    required this.origin,
    this.sha256,
  });

  /// Parses a stored record.
  factory fromJson(Map<String, Object?> json) => InstalledPlugin(
    manifest: PluginManifest.fromJson(
      (json['manifest']! as Map).cast<String, Object?>(),
    ),
    source: json['source']! as String,
    origin: json['origin']! as String,
    sha256: json['sha256'] as String?,
  );

  /// Manifest of the installed version.
  final PluginManifest manifest;

  /// The JS source.
  final String source;

  /// Index URL it came from, or a tag such as `mangayomi` for converted ones.
  final String origin;

  /// Verified digest of [source], when the index supplied one.
  final String? sha256;

  /// Serialised form.
  Map<String, Object?> toJson() => {
    'manifest': manifest.toJson(),
    'source': source,
    'origin': origin,
    'sha256': sha256,
  };
}

/// Plugin repo list, installed plugins and per-plugin prefs.
class PluginStore {
  /// Creates a store over [kv].
  const new(this.kv);

  /// Backing store.
  final KeyValueStore kv;

  static const _repos = 'plugins.repos';
  static const _installed = 'plugins.installed.';
  static const _prefs = 'plugins.prefs.';
  // Local: not in the sync settings catalog.
  static const _languages = 'plugins.languages';

  /// Configured repo index URLs, in the order added.
  Future<List<String>> repos() async {
    final raw = await kv.get(_repos);
    return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
  }

  /// Replaces the repo list.
  Future<void> setRepos(List<String> urls) => kv.set(_repos, jsonEncode(urls));

  /// Languages the Available list shows, in the order picked; null when the
  /// user never chose (the screen then applies its default).
  Future<List<String>?> languages() async {
    final raw = await kv.get(_languages);
    return raw == null ? null : (jsonDecode(raw) as List).cast<String>();
  }

  /// Replaces the language selection.
  Future<void> setLanguages(List<String> langs) =>
      kv.set(_languages, jsonEncode(langs));

  /// Every installed plugin, sorted by name.
  Future<List<InstalledPlugin>> installed() async {
    final all = await kv.entries(prefix: _installed);
    final out = [
      for (final v in all.values)
        InstalledPlugin.fromJson(
          (jsonDecode(v) as Map).cast<String, Object?>(),
        ),
    ]..sort((a, b) => a.manifest.name.compareTo(b.manifest.name));
    return out;
  }

  /// Saves (or replaces) [p].
  Future<void> put(InstalledPlugin p) =>
      kv.set('$_installed${p.manifest.id}', jsonEncode(p.toJson()));

  /// Deletes plugin [id] and its prefs.
  Future<void> remove(String id) async {
    await kv.remove('$_installed$id');
    final prefs = await kv.entries(prefix: '$_prefs$id.');
    for (final k in prefs.keys) {
      await kv.remove(k);
    }
  }

  /// Pref [key] of plugin [id].
  Future<String?> prefGet(String id, String key) => kv.get('$_prefs$id.$key');

  /// Sets pref [key] of plugin [id].
  Future<void> prefSet(String id, String key, String value) =>
      kv.set('$_prefs$id.$key', value);
}
