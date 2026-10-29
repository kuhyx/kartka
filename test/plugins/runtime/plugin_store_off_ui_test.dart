import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/sync/off_ui_json.dart';

InstalledPlugin _plugin(String id, {int kib = 30}) => InstalledPlugin(
  manifest: PluginManifest(
    id: id,
    name: 'Plugin $id',
    version: '1.0.0',
    lang: 'en',
    baseUrl: 'https://$id.example',
  ),
  source: 'x' * (kib * 1024),
  origin: 'test',
);

void main() {
  test(
    'installed plugins (big JS sources) decode off the UI isolate',
    () async {
      final kv = MemoryKeyValueStore();
      final store = PluginStore(kv);
      for (final id in ['c', 'a', 'b']) {
        await store.put(_plugin(id));
      }
      final before = offUiRuns;

      final all = await store.installed();

      expect([for (final p in all) p.manifest.id], ['a', 'b', 'c']);
      expect(all.first.source, hasLength(30 * 1024));
      // Before: ~90 KiB of JSON parsed on the UI isolate (no isolate run).
      expect(offUiRuns, before + 1);
    },
  );

  test('a row that is not a JSON object is a FormatException', () async {
    for (final bad in ['{nope', '[1]']) {
      final kv = MemoryKeyValueStore({
        'plugins.installed.bad': bad,
        'plugins.installed.ok': jsonEncode(_plugin('ok', kib: 1).toJson()),
      });
      await expectLater(
        PluginStore(kv).installed(),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
