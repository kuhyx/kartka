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

/// Updates the Suwayomi-Server's outdated extensions (implemented by the
/// same API as [SuwayomiExtensionInstaller]). Nothing else updates them,
/// and a stale one can break: Atsumaru 1.6.25's search answered HTTP 400.
abstract interface class SuwayomiExtensionUpdater {
  /// Package names of the installed extensions the store has a newer build
  /// of; throws when unreadable.
  Future<List<String>> outdatedPackages();

  /// Updates [pkg] to the store's build.
  Future<void> updateExtension(String pkg);
}

/// Each installed extension package's source ids (the in-app store knows
/// them; a Suwayomi server's list does not).
abstract interface class ExtensionSourceLister {
  /// Package name to its sources' kartka ids.
  Future<Map<String, Set<String>>> packageSources();
}

/// Removes an extension on its own (a rejected source), unlike a user
/// uninstall, which marks it.
abstract interface class ExtensionRemover {
  /// Uninstalls [pkg].
  Future<void> removeExtension(String pkg);
}
