import 'dart:convert';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_index.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_repo_adapter.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';
import 'package:kartka/plugins/runtime/plugin_registrar.dart';

/// Browses a Mangayomi repo and installs its extensions through the
/// runtime's [PluginRegistrar] (origin `mangayomi`).
///
/// Interim path until the Plugins screen consults [MangayomiRepoAdapter]
/// itself; both share the same adapter, so behaviour is identical.
class MangayomiRepoService {
  /// Creates a service. [registrar] is resolved lazily (registry lookup).
  MangayomiRepoService({
    required this.http,
    required this.registrar,
    MangayomiRepoAdapter? adapter,
  }) : adapter = adapter ?? MangayomiRepoAdapter();

  /// HTTP for the index and the extension files.
  final KartkaHttp http;

  /// Where converted plugins are installed.
  final PluginRegistrar? Function() registrar;

  /// Index parsing and conversion.
  final MangayomiRepoAdapter adapter;

  Future<String> _fetch(Uri url) async {
    final res = await http.get(url);
    if (!res.ok) throw KartkaHttpException(url, res.statusCode);
    return res.body;
  }

  /// Installable JS manga extensions of [repo] (index URL, repo root or
  /// GitHub `owner/repo`). Throws [FormatException] for a non-Mangayomi
  /// index and [KartkaHttpException] for an HTTP failure.
  Future<List<PluginIndexEntry>> browse(String repo) async {
    final url = MangayomiIndex.indexUrl(repo);
    final Object? json;
    try {
      json = jsonDecode(await _fetch(url));
    } on FormatException catch (e) {
      throw FormatException('Mangayomi index is not JSON: ${e.message}');
    }
    if (!adapter.accepts(json)) {
      throw FormatException('not a Mangayomi repo index: $url');
    }
    return adapter.parse(json, url);
  }

  /// Fetches, converts and installs [entry] (from [browse]).
  Future<void> install(PluginIndexEntry entry) async {
    final target = registrar();
    if (target == null) throw StateError('plugin runtime is not available');
    final js = await adapter.buildSource(entry, await _fetch(entry.url));
    await target.installLocal(entry.manifest, js, origin: 'mangayomi');
  }
}
