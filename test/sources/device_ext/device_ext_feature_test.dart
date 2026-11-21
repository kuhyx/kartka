import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_extension_runtime.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/source_health/install/uninstall_marks.dart';
import 'package:kartka/sources/device_ext/device_ext_api.dart';
import 'package:kartka/sources/device_ext/device_ext_feature.dart';
import 'package:kartka/sources/suwayomi/suwayomi_feature.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source_provider.dart';
import 'package:material_ui/material_ui.dart';

Map<String, Object?> inventory(List<String> ids) => {
  'installed': [
    {
      'pkg': 'p',
      'name': 'P',
      'versionName': '1.6.1',
      'versionCode': 1,
      'sources': [
        for (final id in ids)
          {'id': id, 'name': 'S', 'lang': 'en', 'supportsLatest': false},
      ],
    },
  ],
};

/// Records the synced keys written.
class _Sync implements SettingsSync {
  final keys = <String>[];

  @override
  Future<void> changed(String key, String? value, SettingsVault vault) async =>
      keys.add(key);

  @override
  Stream<String> get remoteChanges => const Stream.empty();

  @override
  Stream<Map<String, String>> watchProblems() => const Stream.empty();
}

void main() {
  test('uninstall marks are a synced setting on the phone too', () async {
    final sync = _Sync();
    final registry = KartkaRegistry.build(
      memoryPlatform(extensions: FakeExtensionRuntime()),
      [
        suwayomiFeature,
        (_) => KartkaFeature(id: 'sync', services: [sync]),
      ],
    );
    await registry.maybe<DeviceExtensionsApi>()!.marks!.mark('p');
    expect(sync.keys, [UninstallMarks.kvKey]);
  });

  test('Android (a runtime) gets the in-app part, never a server', () {
    final runtime = FakeExtensionRuntime();
    final registry = KartkaRegistry.build(memoryPlatform(extensions: runtime), [
      suwayomiFeature,
    ]);
    expect(registry.features.single.id, 'source-suwayomi');
    expect(registry.all<DeviceExtensionsApi>(), hasLength(1));
    expect(registry.all<DeviceExtSourceProvider>(), hasLength(1));
    expect(registry.all<SuwayomiSourceProvider>(), isEmpty);
    final web = KartkaRegistry.build(memoryPlatform(), [suwayomiFeature]);
    expect(web.all<SuwayomiSourceProvider>(), hasLength(1));
  });

  test('the provider re-lists on refresh and on store changes', () async {
    var ids = ['1'];
    final runtime = FakeExtensionRuntime(handler: (m, a) => inventory(ids));
    final api = DeviceExtensionsApi(
      runtime: runtime,
      http: memoryPlatform().http,
    );
    final provider = DeviceExtSourceProvider(api: api, runtime: runtime);
    final seen = <List<String>>[];
    final sub = provider.watch().listen(
      (s) => seen.add([for (final x in s) x.ref.id]),
    );
    await pumpEventQueue();
    ids = ['1', '2'];
    await api.uninstall('p'); // re-reads 'installed' -> two sources
    await provider.refresh();
    await pumpEventQueue();
    expect(seen.first, ['suwayomi:1']);
    expect(seen.last, ['suwayomi:1', 'suwayomi:2']);
    await sub.cancel();
  });

  test('a runtime that cannot start lists no sources', () async {
    final runtime = FakeExtensionRuntime(
      handler: (m, a) => throw StateError('x'),
    );
    final api = DeviceExtensionsApi(
      runtime: runtime,
      http: memoryPlatform().http,
    );
    final provider = DeviceExtSourceProvider(api: api, runtime: runtime);
    expect(await provider.watch().first, isEmpty);
  });

  testWidgets('the settings tile opens the extensions screen', (tester) async {
    final feature = buildDeviceExtFeature(
      KartkaEnv(memoryPlatform()),
      FakeExtensionRuntime(),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Builder(builder: (c) => feature.settingsTiles.single(c)),
          ),
        ),
        ...feature.routes,
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byType(ListTile));
    await tester.pump();
    expect(router.state.uri.path, suwayomiExtensionsRoute);
  });
}
