import 'dart:async';

import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_registrar.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';
import 'package:kartka/plugins/runtime/plugin_source.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

/// Builds the host services of one installed plugin.
typedef HostServicesFactory = PluginHostServices Function(String pluginId);

/// Installed plugins as sources, live: install and uninstall re-emit.
///
/// Sessions are reused while a plugin's id, version and source are unchanged
/// and disposed when it is removed or replaced.
class PluginSourceProvider implements SourceProvider {
  /// Creates the provider over [registrar].
  new({
    required this.registrar,
    required this.services,
    required this.engineFactory,
  });

  /// Supplies the installed set.
  final PluginRegistrar registrar;

  /// Per-plugin host services.
  final HostServicesFactory services;

  /// Engine for each session.
  final JsEngineFactory engineFactory;

  final Map<String, ({InstalledPlugin plugin, PluginSource source})> _live = {};

  /// Never ends in silence: an unreadable installed list (or a failing
  /// sync) re-emits the last good list, or `[]` before there is one, so the
  /// library's "unavailable source" badges can show.
  @override
  Stream<List<MangaSource>> watch() {
    List<MangaSource>? last;
    return registrar
        .watchInstalled()
        .asyncMap(_sync)
        .transform(
          StreamTransformer.fromHandlers(
            handleData: (sources, sink) => sink.add(last = sources),
            handleError: (_, _, sink) => sink.add(last ?? const []),
          ),
        );
  }

  Future<List<MangaSource>> _sync(List<InstalledPlugin> installed) async {
    final ids = {for (final p in installed) p.manifest.id};
    for (final id in _live.keys.toList()) {
      final old = _live[id]!;
      final now = installed.where((p) => p.manifest.id == id).firstOrNull;
      if (now == null ||
          now.manifest.version != old.plugin.manifest.version ||
          now.source != old.plugin.source) {
        _live.remove(id);
        try {
          await old.source.session.dispose();
        } on Object {
          // A hung engine must not keep its removed plugin listed: the
          // session is already detached, so the sync goes on.
        }
      }
    }
    for (final p in installed) {
      _live.putIfAbsent(p.manifest.id, () {
        final session = PluginSession(
          manifest: p.manifest,
          source: p.source,
          services: services(p.manifest.id),
          engineFactory: engineFactory,
        );
        return (plugin: p, source: PluginSource(session));
      });
    }
    return [
      for (final p in installed)
        if (ids.contains(p.manifest.id)) _live[p.manifest.id]!.source,
    ];
  }
}
