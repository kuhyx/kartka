import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_queries.dart';

/// One Tachiyomi extension known to the server (installed or available).
class SuwayomiExtension {
  /// Creates the extension.
  const new({
    required this.pkgName,
    required this.name,
    required this.lang,
    required this.versionName,
    required this.iconUrl,
    required this.isInstalled,
    required this.hasUpdate,
    required this.isObsolete,
  });

  /// Parses an `ExtensionType`, resolving its icon with [resolve].
  factory fromJson(
    Map<String, Object?> json,
    String Function(String) resolve,
  ) => SuwayomiExtension(
    pkgName: json['pkgName']! as String,
    name: json['name']! as String,
    lang: json['lang']! as String,
    versionName: json['versionName']! as String,
    iconUrl: resolve(json['iconUrl']! as String),
    isInstalled: json['isInstalled']! as bool,
    hasUpdate: json['hasUpdate']! as bool,
    isObsolete: json['isObsolete']! as bool,
  );

  /// Android package name; the id every mutation takes.
  final String pkgName;

  /// Display name.
  final String name;

  /// Language code, or `all` / `multi`.
  final String lang;

  /// Version of the installed (or offered) build.
  final String versionName;

  /// Absolute icon URL on the server (needs the auth header).
  final String iconUrl;

  /// Whether it is installed on the server.
  final bool isInstalled;

  /// Whether the store offers a newer version.
  final bool hasUpdate;

  /// Installed but no longer in any store.
  final bool isObsolete;
}

/// Installed first (pending updates on top), then available, each by name.
List<SuwayomiExtension> sortExtensions(Iterable<SuwayomiExtension> all) {
  int rank(SuwayomiExtension e) => e.isInstalled ? (e.hasUpdate ? 0 : 1) : 2;
  return [...all]..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0
        ? byRank
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// Lists, installs, updates and uninstalls the server's extensions; also
/// the Sources tab's [SuwayomiExtensionInstaller] and the Keep
/// auto-install's [InstalledExtensionLister].
class SuwayomiExtensionsApi
    implements SuwayomiExtensionInstaller, InstalledExtensionLister {
  /// Creates the API; [onChanged] runs after every successful change (the
  /// feature re-lists the sources there).
  new({required this.client, required this.settings, this.onChanged});

  /// GraphQL client.
  final SuwayomiClient client;

  /// Current settings (icon URLs).
  final SettingsReader settings;

  /// Called after install / update / uninstall.
  final Future<void> Function()? onChanged;

  /// Every extension in the server's stores, refreshed from the stores.
  Future<List<SuwayomiExtension>> list() async {
    final data = await client.run(SuwayomiQueries.extensions);
    final payload = data['fetchExtensions']! as Map<String, Object?>;
    final resolve = settings().resolve;
    return sortExtensions([
      for (final e in payload['extensions']! as List<Object?>)
        SuwayomiExtension.fromJson(e! as Map<String, Object?>, resolve),
    ]);
  }

  /// Installs [pkgName].
  Future<SuwayomiExtension> install(String pkgName) =>
      _patch(pkgName, 'install');

  @override
  Future<void> installExtension(String pkg) => install(pkg);

  @override
  Future<Set<String>> installedPackages() async => {
    for (final e in await list())
      if (e.isInstalled) e.pkgName,
  };

  /// Updates [pkgName] to the store's version.
  Future<SuwayomiExtension> update(String pkgName) => _patch(pkgName, 'update');

  /// Uninstalls [pkgName].
  Future<SuwayomiExtension> uninstall(String pkgName) =>
      _patch(pkgName, 'uninstall');

  Future<SuwayomiExtension> _patch(String pkgName, String action) async {
    final data = await client.run(SuwayomiQueries.updateExtension, {
      'id': pkgName,
      'patch': {action: true},
    });
    final payload = data['updateExtension']! as Map<String, Object?>;
    final extension = SuwayomiExtension.fromJson(
      payload['extension']! as Map<String, Object?>,
      settings().resolve,
    );
    await onChanged?.call();
    return extension;
  }
}
