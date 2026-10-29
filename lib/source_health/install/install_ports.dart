/// Ports the Sources tab's Install button uses (DOCS-contracts §3: declared
/// by the consumer, implemented and registered by the owning part).
library;

/// Installs a Tachiyomi extension on the configured Suwayomi-Server
/// (implemented by the Suwayomi part's extensions API).
abstract interface class SuwayomiExtensionInstaller {
  /// Installs extension package [pkg]; the part re-lists its sources after.
  Future<void> installExtension(String pkg);
}

/// Installs a Kartka plugin from a repo index (implemented by the plugin
/// manager).
abstract interface class PluginRepoInstaller {
  /// Installs plugin [id] offered by the repo index at [repo].
  Future<void> installPlugin({required String repo, required String id});
}

/// Lists the extensions installed on the Suwayomi-Server (implemented by the
/// same API as [SuwayomiExtensionInstaller]). The Keep auto-install reads
/// it, never the source list: that list is empty while the server is slow.
abstract interface class InstalledExtensionLister {
  /// Package names of every installed extension; throws when unreadable.
  Future<Set<String>> installedPackages();
}

/// Lists the plugins installed on this device (implemented by the plugin
/// manager next to [PluginRepoInstaller]).
abstract interface class InstalledPluginLister {
  /// Ids of every installed plugin; throws when unreadable.
  Future<Set<String>> installedPluginIds();
}
