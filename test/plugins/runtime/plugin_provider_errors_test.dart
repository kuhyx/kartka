import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/kartka_host_services.dart';
import 'package:kartka/plugins/runtime/plugin_registrar.dart';
import 'package:kartka/plugins/runtime/plugin_source_provider.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

import 'support.dart';

/// A registrar whose installed list is whatever the test pushes.
class _Registrar implements PluginRegistrar {
  final installed = StreamController<List<InstalledPlugin>>();

  @override
  Stream<List<InstalledPlugin>> watchInstalled() => installed.stream;

  @override
  Future<void> installLocal(
    PluginManifest manifest,
    String source, {
    required String origin,
  }) async {}

  @override
  Future<void> uninstall(String id) async {}
}

void main() {
  late _Registrar registrar;
  late PluginSourceProvider provider;
  setUp(() {
    final http = FakeHttp();
    final store = PluginStore(MemoryKeyValueStore());
    registrar = _Registrar();
    provider = PluginSourceProvider(
      registrar: registrar,
      services: (id) =>
          KartkaHostServices(pluginId: id, http: http.client, store: store),
      engineFactory: QuickJsEngine.new,
    );
  });

  const demo = InstalledPlugin(
    manifest: PluginManifest(
      id: 'demo',
      name: 'Demo',
      version: '1.0.0',
      lang: 'en',
      baseUrl: 'https://demo.test',
    ),
    source: 'x',
    origin: 'test',
  );

  test('an unreadable installed list still emits [] (badges show)', () async {
    final emitted = <int>[];
    final errors = <Object>[];
    provider.watch().listen((s) => emitted.add(s.length), onError: errors.add);
    registrar.installed.addError(StateError('corrupt store'));
    await pumpEventQueue();
    expect(emitted, [0]);
    expect(errors, isEmpty);
  });

  test('a later failure keeps the last good list', () async {
    final emitted = <List<String>>[];
    provider.watch().listen((s) => emitted.add([for (final x in s) x.ref.id]));
    registrar.installed
      ..add([demo])
      ..addError(StateError('corrupt store'));
    await pumpEventQueue();
    expect(emitted, [
      ['plugin:demo'],
      ['plugin:demo'],
    ]);
  });
}
