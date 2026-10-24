import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

/// Port other parts use to put plugins into the same store, provider and
/// Plugins screen as repo-installed ones.
///
/// The Mangayomi converter looks it up with
/// `env.registry.maybe<PluginRegistrar>()` (lazily, never while building) and
/// calls [installLocal] with the converted manifest and shim JS. The plugin
/// then appears as source `plugin:<id>` through the plugins feature's
/// `SourceProvider`, with no provider of its own.
abstract interface class PluginRegistrar {
  /// Installs or replaces plugin [manifest] with JS [source].
  ///
  /// [origin] labels where it came from in the UI (for example `mangayomi`).
  Future<void> installLocal(
    PluginManifest manifest,
    String source, {
    required String origin,
  });

  /// Removes plugin [id] and its prefs; a missing id is not an error.
  Future<void> uninstall(String id);

  /// Installed plugins, emitted now and after every change.
  Stream<List<InstalledPlugin>> watchInstalled();
}
