import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_repo_adapter.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

import 'support.dart';

/// Accepts `{"foreign": [...]}` indexes and wraps the JS it downloads.
class ForeignAdapter implements PluginRepoAdapter {
  new({this.fail = false});
  final bool fail;
  final List<String> built = [];

  @override
  bool accepts(Object? indexJson) =>
      indexJson is Map && indexJson['foreign'] != null;

  @override
  List<PluginIndexEntry> parse(Object? json, Uri indexUrl) => [
    for (final raw in (json! as Map)['foreign'] as List)
      PluginIndexEntry(
        manifest: PluginManifest(
          id: (raw as Map)['id'] as String,
          name: raw['name'] as String,
          version: '1',
          lang: 'en',
          baseUrl: 'https://foreign.test',
        ),
        url: indexUrl.resolve(raw['file'] as String),
        repoUrl: indexUrl.toString(),
        adapter: this,
      ),
  ];

  @override
  Future<String> buildSource(PluginIndexEntry e, String fetchedJs) async {
    if (fail) throw StateError('cannot convert');
    built.add(e.manifest.id);
    return '/* converted */\n$fetchedJs';
  }
}

void main() {
  const foreign = 'https://repo.test/foreign.json';
  late FakeHttp http;
  late PluginStore store;

  setUp(() {
    http = FakeHttp();
    store = PluginStore(MemoryKeyValueStore());
    http.overrides[foreign] = (
      status: 200,
      body: '{"foreign":[{"id":"f1","name":"Foreign One","file":"demo.js"}]}',
    );
  });

  PluginManager make(List<PluginRepoAdapter> adapters) =>
      PluginManager(http: http.client, store: store, adapters: () => adapters);

  test('an accepting adapter lists entries and converts on install', () async {
    final a = ForeignAdapter();
    final m = make([a]);
    await m.addRepo(foreign);
    final offers = (await m.available()).plugins;
    expect(offers.single.entry.manifest.id, 'f1');
    await m.install(offers.single.entry);
    final p = (await store.installed()).single;
    expect(p.source, startsWith('/* converted */'));
    expect(p.source, contains('function popular'));
    expect(a.built, ['f1']);
  });

  test('the first accepting adapter wins; native indexes still work', () async {
    final first = ForeignAdapter();
    final second = ForeignAdapter();
    final m = make([first, second]);
    await m.addRepo(foreign);
    await m.addRepo('https://repo.test/index.json');
    final ids = (await m.available()).plugins.map((p) => p.entry.manifest.id);
    expect(ids, ['f1', 'demo', 'nohash']);
    final native = (await m.available()).plugins.last.entry;
    expect(native.adapter, isNull);
    await m.install(native);
    expect(first.built, isEmpty);
    expect(second.built, isEmpty);
  });

  test('a failing conversion surfaces as a PluginException', () async {
    final m = make([ForeignAdapter(fail: true)]);
    await m.addRepo(foreign);
    final entry = (await m.available()).plugins.single.entry;
    await expectLater(
      m.install(entry),
      throwsA(
        isA<PluginException>()
            .having((e) => e.pluginId, 'id', 'f1')
            .having((e) => e.message, 'm', contains('conversion failed')),
      ),
    );
    expect(await store.installed(), isEmpty);
  });

  test('without adapters a foreign index is rejected as native', () async {
    await expectLater(make([]).addRepo(foreign), throwsFormatException);
  });
}
