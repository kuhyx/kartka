import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_registrar.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/plugins/runtime/plugins_feature.dart';

import 'support.dart';

void main() {
  test('a failing repo index is logged as plugins.repo', () async {
    final kv = MemoryKeyValueStore();
    final platform = memoryPlatform(http: FakeHttp().client, kv: kv);
    final registry = KartkaRegistry.build(platform, [
      (env) => pluginsFeature(env, engineFactory: QuickJsEngine.new),
    ]);
    final manager = registry.maybe<PluginRegistrar>()! as PluginManager;
    await PluginStore(kv).setRepos(['https://repo.test/gone.json']);
    expect((await manager.available()).errors, hasLength(1));
    final log = await DiagnosticsLog.of(platform.diagnostics).entries();
    expect(log.single.kind, 'plugins.repo');
  });
}
