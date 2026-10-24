import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/kartka_host_services.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_source_provider.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

import 'support.dart';

void main() {
  const repo = 'https://repo.test/index.json';
  late FakeHttp http;
  late PluginStore store;
  late PluginManager manager;
  late PluginSourceProvider provider;
  late List<List<MangaSource>> emissions;

  setUp(() {
    http = FakeHttp();
    store = PluginStore(MemoryKeyValueStore());
    manager = PluginManager(http: http.client, store: store);
    provider = PluginSourceProvider(
      registrar: manager,
      services: (id) =>
          KartkaHostServices(pluginId: id, http: http.client, store: store),
      engineFactory: QuickJsEngine.new,
    );
    emissions = [];
  });

  test('repo to installed source to chapter pages, end to end', () async {
    final sub = provider.watch().listen(emissions.add);
    await manager.addRepo(repo);
    final offer = (await manager.available()).plugins.first.entry;
    await manager.install(offer);
    await pumpEventQueue();

    final source = emissions.last.single;
    expect(source.ref.id, 'plugin:demo');
    expect(source.ref.origin, SourceOrigin.plugin);
    expect(source.ref.name, 'Demo Site');

    final popular = await source.popular(1);
    expect(popular.items.map((i) => i.title), ['One Piece', 'Berserk']);
    expect(popular.items.first.sourceId, 'plugin:demo');
    expect((await source.latest(1)).hasNext, false);
    expect((await source.search('bers erk', 1)).items.single.title, 'Berserk');
    final d = await source.details('/m/1');
    expect(d.genres, ['Adventure', 'Comedy']);
    final ch = await source.chapters('/m/1');
    expect(ch.map((c) => c.number), [2.0, 1.5]);
    final pages = await source.pages('/m/1/c/1');
    expect(pages.map((p) => p.imageUrl), [
      'https://img.demo.test/1/1.jpg',
      'https://img.demo.test/1/2.jpg',
    ]);
    expect(pages.first.headers['Referer'], 'https://demo.test/');
    expect(http.requested.any((r) => r.contains('demo.test/popular')), true);
    await sub.cancel();
  });

  test(
    'uninstall removes the source; reinstall at same version reuses',
    () async {
      final sub = provider.watch().listen(emissions.add);
      await manager.addRepo(repo);
      final entry = (await manager.available()).plugins.first.entry;
      await manager.install(entry);
      await pumpEventQueue();
      final first = emissions.last.single;
      await manager.install(entry);
      await pumpEventQueue();
      expect(identical(emissions.last.single, first), true);
      await manager.uninstall('demo');
      await pumpEventQueue();
      expect(emissions.last, isEmpty);
      await sub.cancel();
    },
  );

  test(
    'a new version replaces the source and a failing plugin names itself',
    () async {
      final sub = provider.watch().listen(emissions.add);
      const m = PluginManifest(
        id: 'p',
        name: 'P',
        version: '1',
        lang: 'en',
        baseUrl: 'https://p.test',
      );
      await manager.installLocal(
        m,
        'function popular(p) { throw new Error("x"); }',
        origin: 'test',
      );
      await pumpEventQueue();
      final first = emissions.last.single;
      await expectLater(
        first.popular(1),
        throwsA(isA<PluginException>().having((e) => e.pluginId, 'id', 'p')),
      );
      await manager.installLocal(
        const PluginManifest(
          id: 'p',
          name: 'P',
          version: '2',
          lang: 'en',
          baseUrl: 'https://p.test',
        ),
        'function popular(p) { return {items: []}; }',
        origin: 'test',
      );
      await pumpEventQueue();
      final second = emissions.last.single;
      expect(identical(first, second), false);
      expect((await second.popular(1)).items, isEmpty);
      await sub.cancel();
    },
  );
}
