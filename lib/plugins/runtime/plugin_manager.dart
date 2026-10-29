import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';
import 'package:kartka/plugins/runtime/plugin_registrar.dart';
import 'package:kartka/plugins/runtime/plugin_repo_adapter.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/source_health/install/install_ports.dart';

/// Largest plugin file accepted.
const int kMaxPluginBytes = 1024 * 1024;

/// What the Plugins screen shows for an index entry.
enum PluginAvailability {
  /// Not installed.
  available,

  /// Installed at the same or a newer version.
  installed,

  /// Installed, and the repo offers a newer version.
  updatable,
}

/// An index entry plus its state against what is installed.
class AvailablePlugin {
  /// Creates the pair.
  const new(this.entry, this.availability);

  /// The repo's offer.
  final PluginIndexEntry entry;

  /// State against the installed set.
  final PluginAvailability availability;
}

/// Result of reading every repo: plugins plus per-repo failures.
class AvailableResult {
  /// Creates a result.
  const new(this.plugins, this.errors);

  /// Offers from repos that answered.
  final List<AvailablePlugin> plugins;

  /// Repo URL to message, for repos that failed.
  final Map<String, String> errors;
}

/// Repo management and install/update/uninstall.
class PluginManager
    implements PluginRegistrar, PluginRepoInstaller, InstalledPluginLister {
  /// Creates a manager.
  new({required this.http, required this.store, this.adapters = _noAdapters});

  /// All downloads go through this.
  final KartkaHttp http;

  /// Persistence.
  final PluginStore store;

  /// Extra repo formats, asked lazily (registry order) on every index read.
  final List<PluginRepoAdapter> Function() adapters;

  static List<PluginRepoAdapter> _noAdapters() => const [];

  final StreamController<void> _changes = StreamController.broadcast();

  Future<List<PluginIndexEntry>> _fetchIndex(String url) async {
    final u = Uri.parse(url);
    final r = await http.get(u);
    if (!r.ok) throw KartkaHttpException(u, r.statusCode);
    final json = decodeIndexJson(r.body);
    for (final a in adapters()) {
      if (a.accepts(json)) return a.parse(json, u);
    }
    return parseNativeIndex(json, u);
  }

  /// Adds repo [url] after checking that it serves a valid index.
  ///
  /// Throws [FormatException] for a bad URL or index, or
  /// [KartkaHttpException] for a non-2xx answer. Adding twice is a no-op.
  Future<void> addRepo(String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null || !isHttpUrl(u)) {
      throw FormatException('repo URL must be http(s): $url');
    }
    final clean = u.toString();
    final repos = await store.repos();
    if (repos.contains(clean)) return;
    await _fetchIndex(clean);
    await store.setRepos([...repos, clean]);
  }

  /// Removes repo [url]; installed plugins stay installed.
  Future<void> removeRepo(String url) async {
    final repos = await store.repos();
    await store.setRepos([...repos]..remove(url));
  }

  /// Configured repo URLs.
  Future<List<String>> repos() => store.repos();

  /// Everything every repo offers, marked against the installed set.
  Future<AvailableResult> available() async {
    final installed = {
      for (final p in await store.installed()) p.manifest.id: p.manifest,
    };
    final plugins = <AvailablePlugin>[];
    final errors = <String, String>{};
    for (final repo in await store.repos()) {
      try {
        for (final e in await _fetchIndex(repo)) {
          final have = installed[e.manifest.id];
          plugins.add(AvailablePlugin(e, _state(have, e.manifest)));
        }
      } on Object catch (e) {
        errors[repo] = '$e';
      }
    }
    return AvailableResult(plugins, errors);
  }

  PluginAvailability _state(PluginManifest? have, PluginManifest offered) {
    if (have == null) return PluginAvailability.available;
    return isNewerVersion(offered.version, have.version)
        ? PluginAvailability.updatable
        : PluginAvailability.installed;
  }

  /// Downloads, verifies and stores [entry] (also used to update).
  ///
  /// Verifies `sha256` when the index has one. Throws [PluginException].
  Future<void> install(PluginIndexEntry entry) async {
    final id = entry.manifest.id;
    final KartkaResponse r;
    try {
      r = await http.get(entry.url);
    } on Object catch (e) {
      throw PluginException(id, 'download failed: $e');
    }
    if (!r.ok) {
      throw PluginException(id, 'download failed: HTTP ${r.statusCode}');
    }
    if (r.bodyBytes.isEmpty || r.bodyBytes.length > kMaxPluginBytes) {
      throw PluginException(id, 'plugin file has an invalid size');
    }
    final digest = sha256.convert(r.bodyBytes).toString();
    if (entry.sha256 != null && entry.sha256 != digest) {
      throw PluginException(id, 'sha256 mismatch (got $digest)');
    }
    final String source;
    try {
      source = await entry.adapter?.buildSource(entry, r.body) ?? r.body;
    } on Object catch (e) {
      throw PluginException(id, 'conversion failed: $e');
    }
    await _save(
      InstalledPlugin(
        manifest: entry.manifest,
        source: source,
        origin: entry.repoUrl ?? 'unknown',
        sha256: entry.sha256,
      ),
    );
  }

  @override
  Future<Set<String>> installedPluginIds() async => {
    for (final p in await store.installed()) p.manifest.id,
  };

  /// The Sources tab's Install: adds [repo] (a no-op when configured; the
  /// repo list syncs), then installs its plugin [id]. Throws
  /// [PluginException] when the repo does not offer it (with the repo's
  /// read error, if any).
  @override
  Future<void> installPlugin({required String repo, required String id}) async {
    await addRepo(repo);
    final offers = await available();
    final offer = offers.plugins
        .where((p) => p.entry.manifest.id == id)
        .firstOrNull;
    if (offer == null) {
      // addRepo stored the URL in this normal form (and validated it).
      final key = Uri.parse(repo.trim()).toString();
      final why = offers.errors[key] ?? 'not offered by its repo';
      throw PluginException(id, why);
    }
    await install(offer.entry);
  }

  Future<void> _save(InstalledPlugin p) async {
    await store.put(p);
    _changes.add(null);
  }

  @override
  Future<void> installLocal(
    PluginManifest manifest,
    String source, {
    required String origin,
  }) => _save(
    InstalledPlugin(manifest: manifest, source: source, origin: origin),
  );

  @override
  Future<void> uninstall(String id) async {
    await store.remove(id);
    _changes.add(null);
  }

  @override
  Stream<List<InstalledPlugin>> watchInstalled() {
    late final StreamController<List<InstalledPlugin>> out;
    StreamSubscription<void>? sub;
    // Reads are chained so emissions keep the order of the changes.
    var tail = Future<void>.value();
    void emit() {
      tail = tail.then((_) async {
        try {
          final list = await store.installed();
          if (!out.isClosed) out.add(list);
        } on Object catch (e, st) {
          if (!out.isClosed) out.addError(e, st);
        }
      });
    }

    out = StreamController<List<InstalledPlugin>>(
      onListen: () {
        sub = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }
}
