import 'dart:async';
import 'dart:typed_data';

import 'package:kartka/platform/extension_runtime.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/sources/device_ext/keiyoushi_index.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';

/// One source of an installed extension, as the runtime lists it.
class DeviceSourceInfo {
  /// Creates the info.
  const new({
    required this.id,
    required this.name,
    required this.lang,
    required this.supportsLatest,
  });

  /// Reads one `sources[]` map of the runtime.
  factory fromMap(Map<Object?, Object?> m) => DeviceSourceInfo(
    id: m['id']! as String,
    name: m['name']! as String,
    lang: m['lang']! as String,
    supportsLatest: m['supportsLatest']! as bool,
  );

  /// Tachiyomi source id (a string: it exceeds 2^53).
  final String id;

  /// Display name.
  final String name;

  /// Language code.
  final String lang;

  /// Whether it has a "latest" listing.
  final bool supportsLatest;
}

class _Installed {
  new(Map<Object?, Object?> m)
    : pkg = m['pkg']! as String,
      name = m['name']! as String,
      versionName = m['versionName']! as String,
      versionCode = m['versionCode']! as int,
      sources = [
        for (final s in m['sources']! as List<Object?>)
          DeviceSourceInfo.fromMap(s! as Map<Object?, Object?>),
      ];

  final String pkg;
  final String name;
  final String versionName;
  final int versionCode;
  final List<DeviceSourceInfo> sources;
}

/// The in-app extension store: Keiyoushi's index, APKs downloaded over
/// [http] and loaded by [runtime]. The Android stand-in for the Suwayomi
/// server's store, behind the same ports (Sources tab install, Keep
/// auto-install, auto-update) and the same extensions screen.
class DeviceExtensionsApi
    implements
        ExtensionCatalog,
        SuwayomiExtensionInstaller,
        InstalledExtensionLister,
        SuwayomiExtensionUpdater {
  /// Creates the API.
  new({required this.runtime, required this.http, this.indexUrl});

  /// The Kotlin host.
  final ExtensionRuntime runtime;

  /// Downloads the index and the APKs.
  final KartkaHttp http;

  /// Store index; null means [keiyoushiIndexUrl].
  final String? indexUrl;

  Future<List<_Installed>>? _loaded;
  Future<List<RepoExtension>>? _index;
  final _changes = StreamController<List<DeviceSourceInfo>>.broadcast();

  /// Every installed source, re-emitted after each change.
  Stream<List<DeviceSourceInfo>> get changes => _changes.stream;

  /// Installed sources, loading the installed APKs on first use.
  Future<List<DeviceSourceInfo>> sources() async => [
    for (final e in await _installed()) ...e.sources,
  ];

  Future<List<_Installed>> _installed() => _loaded ??= _read(
    runtime.invoke('init', {
      'userAgent': kartkaUserAgent,
      'trusted': [keiyoushiSigningKey],
    }),
  );

  Future<List<_Installed>> _read(Future<Object?> reply) async {
    final m = (await reply)! as Map<Object?, Object?>;
    return [
      for (final e in m['installed']! as List<Object?>)
        _Installed(e! as Map<Object?, Object?>),
    ];
  }

  Future<List<RepoExtension>> _store() => _index ??=
      () async {
        final url = Uri.parse(indexUrl ?? keiyoushiIndexUrl);
        final res = await http.get(url);
        if (!res.ok) throw KartkaHttpException(url, res.statusCode);
        return parseKeiyoushiIndex(res.bodyBytes);
      }().catchError((Object e, StackTrace s) {
        _index = null;
        Error.throwWithStackTrace(e, s);
      });

  @override
  Future<List<SuwayomiExtension>> list() async {
    final installed = {for (final e in await _installed()) e.pkg: e};
    final store = await _store();
    final offered = {for (final e in store) e.pkg};
    return sortExtensions([
      for (final e in store)
        SuwayomiExtension(
          pkgName: e.pkg,
          name: e.name,
          lang: e.lang,
          versionName: installed[e.pkg]?.versionName ?? e.versionName,
          iconUrl: e.iconUrl,
          isInstalled: installed.containsKey(e.pkg),
          hasUpdate: (installed[e.pkg]?.versionCode ?? 1 << 62) < e.versionCode,
          isObsolete: false,
        ),
      for (final e in installed.values)
        if (!offered.contains(e.pkg))
          SuwayomiExtension(
            pkgName: e.pkg,
            name: e.name,
            lang: '',
            versionName: e.versionName,
            iconUrl: '',
            isInstalled: true,
            hasUpdate: false,
            isObsolete: true,
          ),
    ]);
  }

  @override
  Future<SuwayomiExtension> install(String pkgName) async {
    final entry = (await _store()).where((e) => e.pkg == pkgName).firstOrNull;
    if (entry == null) {
      throw ExtensionRuntimeException('$pkgName is not in the store');
    }
    final url = Uri.parse(entry.apkUrl);
    final res = await http.get(url);
    if (!res.ok) throw KartkaHttpException(url, res.statusCode);
    await runtime.invoke('install', {'apk': Uint8List.fromList(res.bodyBytes)});
    return await _changed(pkgName);
  }

  @override
  Future<SuwayomiExtension> update(String pkgName) => install(pkgName);

  @override
  Future<SuwayomiExtension> uninstall(String pkgName) async {
    await runtime.invoke('uninstall', {'pkg': pkgName});
    return await _changed(pkgName);
  }

  Future<SuwayomiExtension> _changed(String pkg) async {
    _loaded = _read(runtime.invoke('installed'));
    _changes.add(await sources());
    // The store index only adds icons and update marks: the change itself
    // is done even when it cannot be read.
    final all = await list().catchError((Object _) => <SuwayomiExtension>[]);
    final installed = (await installedPackages()).contains(pkg);
    return all.firstWhere(
      (e) => e.pkgName == pkg,
      orElse: () => SuwayomiExtension(
        pkgName: pkg,
        name: pkg,
        lang: '',
        versionName: '',
        iconUrl: '',
        isInstalled: installed,
        hasUpdate: false,
        isObsolete: installed,
      ),
    );
  }

  @override
  Future<void> installExtension(String pkg) => install(pkg);

  @override
  Future<Set<String>> installedPackages() async => {
    for (final e in await _installed()) e.pkg,
  };

  @override
  Future<List<String>> outdatedPackages() async => [
    for (final e in await list())
      if (e.hasUpdate) e.pkgName,
  ];

  @override
  Future<void> updateExtension(String pkg) => update(pkg);
}
