import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/extension_runtime.dart';
import 'package:kartka/sources/device_ext/device_ext_api.dart';
import 'package:kartka/sources/device_ext/device_ext_source.dart';
import 'package:kartka/sources/suwayomi/suwayomi_feature_builder.dart';
import 'package:kartka/sources/suwayomi/ui/extensions_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Sources of the extensions loaded in-app, re-listed on every change.
class DeviceExtSourceProvider implements RefreshableSourceProvider {
  /// Lists [api]'s sources through [runtime].
  new({required this.api, required this.runtime}) {
    api.changes.listen((infos) => _refreshed.add(_wrap(infos)));
  }

  /// The in-app store.
  final DeviceExtensionsApi api;

  /// The Kotlin host.
  final ExtensionRuntime runtime;

  final _refreshed = StreamController<List<MangaSource>>.broadcast();

  List<MangaSource> _wrap(List<DeviceSourceInfo> infos) => [
    for (final i in infos) DeviceExtSource(info: i, runtime: runtime),
  ];

  Future<List<MangaSource>> _current() async {
    try {
      return _wrap(await api.sources());
    } on Object {
      // A runtime that cannot start lists nothing; Browse shows the rest.
      return const [];
    }
  }

  @override
  Stream<List<MangaSource>> watch() async* {
    yield await _current();
    yield* _refreshed.stream;
  }

  @override
  Future<void> refresh() async => _refreshed.add(await _current());
}

/// The Android stand-in for the Suwayomi part: Keiyoushi extensions run
/// in the app (contracts-runtime §18), so nothing reaches a server. The
/// settings tile opens the same extensions screen, on the in-app store.
KartkaFeature buildDeviceExtFeature(KartkaEnv env, ExtensionRuntime runtime) {
  final api = DeviceExtensionsApi(runtime: runtime, http: env.platform.http);
  final provider = DeviceExtSourceProvider(api: api, runtime: runtime);
  return KartkaFeature(
    id: 'source-suwayomi',
    services: [provider, api],
    settingsTiles: [
      (context) => ListTile(
        leading: const Icon(
          Icons.extension_outlined,
          semanticLabel: 'Extensions',
        ),
        onTap: () => context.push(suwayomiExtensionsRoute),
      ),
    ],
    routes: [
      GoRoute(
        path: suwayomiExtensionsRoute,
        builder: (_, _) => ExtensionsScreen(
          api: api,
          diagnostics: DiagnosticsLog.of(env.platform.diagnostics),
        ),
      ),
    ],
  );
}
