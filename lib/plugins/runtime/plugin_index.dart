import 'dart:convert';

import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_repo_adapter.dart';

/// One plugin offered by a repo's `index.json`.
///
/// Index shape: `{"plugins": [{...manifest fields, "url": "(js file)",
/// "sha256"?: "(hex)"}]}`; `url` may be relative to the index URL.
class PluginIndexEntry {
  /// Creates an entry.
  const new({
    required this.manifest,
    required this.url,
    this.sha256,
    this.repoUrl,
    this.adapter,
  });

  /// The plugin's manifest.
  final PluginManifest manifest;

  /// Absolute http(s) URL of the plugin's JS file.
  final Uri url;

  /// Expected lowercase hex SHA-256 of the JS file, when the index has one.
  final String? sha256;

  /// URL of the index this entry came from.
  final String? repoUrl;

  /// Set when a `PluginRepoAdapter` parsed this entry; it converts the
  /// downloaded file at install time.
  final PluginRepoAdapter? adapter;
}

/// Parses a native `index.json` body fetched from [indexUrl].
///
/// Throws [FormatException] naming the offending entry.
List<PluginIndexEntry> parsePluginIndex(String body, Uri indexUrl) =>
    parseNativeIndex(decodeIndexJson(body), indexUrl);

/// Decodes an index body; throws [FormatException] if it is not JSON.
Object? decodeIndexJson(String body) {
  try {
    return jsonDecode(body);
  } on FormatException catch (e) {
    throw FormatException('index is not JSON: ${e.message}');
  }
}

/// Parses an already decoded native index.
List<PluginIndexEntry> parseNativeIndex(Object? root, Uri indexUrl) {
  final list = root is Map ? root['plugins'] : null;
  if (list is! List) throw const FormatException('index has no "plugins" list');
  final entries = <PluginIndexEntry>[];
  for (final (i, raw) in list.indexed) {
    try {
      entries.add(_entry(raw, indexUrl));
    } on FormatException catch (e) {
      throw FormatException('plugin #$i: ${e.message}');
    }
  }
  return entries;
}

PluginIndexEntry _entry(Object? raw, Uri indexUrl) {
  if (raw is! Map) throw const FormatException('not an object');
  final json = raw.cast<String, Object?>();
  final manifest = PluginManifest.fromJson(json);
  final url = json['url'];
  if (url is! String) throw const FormatException('missing "url"');
  final resolved = indexUrl.resolve(url);
  if (!isHttpUrl(resolved)) {
    throw FormatException('"url" must be http(s): $resolved');
  }
  final hash = json['sha256'];
  if (hash != null && (hash is! String || !_hex.hasMatch(hash))) {
    throw const FormatException('"sha256" must be 64 hex characters');
  }
  return PluginIndexEntry(
    manifest: manifest,
    url: resolved,
    sha256: (hash as String?)?.toLowerCase(),
    repoUrl: indexUrl.toString(),
  );
}

final RegExp _hex = RegExp(r'^[0-9a-fA-F]{64}$');

/// True for absolute `http`/`https` URLs with a host.
bool isHttpUrl(Uri u) =>
    (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;

/// True when version [a] is newer than [b] (dotted numbers; any non-numeric
/// part makes two different strings count as newer, so updates are offered).
bool isNewerVersion(String a, String b) {
  if (a == b) return false;
  final pa = a.split('.').map(int.tryParse).toList();
  final pb = b.split('.').map(int.tryParse).toList();
  if (pa.contains(null) || pb.contains(null)) return true;
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i]! : 0;
    final y = i < pb.length ? pb[i]! : 0;
    if (x != y) return x > y;
  }
  return false;
}
