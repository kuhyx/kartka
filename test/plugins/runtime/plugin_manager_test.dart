import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

import 'support.dart';

void main() {
  const repo = 'https://repo.test/index.json';
  late FakeHttp http;
  late MemoryKeyValueStore kv;
  late PluginStore store;
  late PluginManager m;

  setUp(() {
    http = FakeHttp();
    kv = MemoryKeyValueStore();
    store = PluginStore(kv);
    m = PluginManager(http: http.client, store: store);
  });

  test('addRepo validates the index, dedupes and persists', () async {
    await m.addRepo(' $repo ');
    await m.addRepo(repo);
    expect(await m.repos(), [repo]);
    expect(http.requested, hasLength(1));
  });

  test('addRepo rejects bad urls and bad or missing indexes', () async {
    await expectLater(m.addRepo('ftp://x/i.json'), throwsFormatException);
    await expectLater(m.addRepo('::'), throwsFormatException);
    await expectLater(
      m.addRepo('https://repo.test/missing.json'),
      throwsA(isA<KartkaHttpException>()),
    );
    http.overrides['https://repo.test/bad.json'] = (status: 200, body: '{}');
    await expectLater(
      m.addRepo('https://repo.test/bad.json'),
      throwsFormatException,
    );
    expect(await m.repos(), isEmpty);
  });

  test('removeRepo forgets the repo but keeps installed plugins', () async {
    await m.addRepo(repo);
    final offer = (await m.available()).plugins.first.entry;
    await m.install(offer);
    await m.removeRepo(repo);
    expect(await m.repos(), isEmpty);
    expect(await store.installed(), hasLength(1));
  });

  test(
    'available lists offers with install state, repo errors apart',
    () async {
      await store.setRepos([repo, 'https://repo.test/gone.json']);
      var r = await m.available();
      expect(
        r.plugins.map((p) => p.availability),
        everyElement(PluginAvailability.available),
      );
      expect(r.errors.keys, ['https://repo.test/gone.json']);
      final heard = <String>[];
      final told = PluginManager(
        http: http.client,
        store: store,
        onRepoError: (repo, e, _) => heard.add(repo),
      );
      await told.available();
      expect(heard, ['https://repo.test/gone.json']);
      await m.install(r.plugins.first.entry);
      r = await m.available();
      expect(r.plugins.first.availability, PluginAvailability.installed);
      await store.put(
        const InstalledPlugin(
          manifest: PluginManifest(
            id: 'demo',
            name: 'Demo',
            version: '0.9.0',
            lang: 'en',
            baseUrl: 'https://demo.test',
          ),
          source: 'x',
          origin: repo,
        ),
      );
      r = await m.available();
      expect(r.plugins.first.availability, PluginAvailability.updatable);
    },
  );

  test('install verifies sha256 and stores the plugin', () async {
    await store.setRepos([repo]);
    final entry = (await m.available()).plugins.first.entry;
    await m.install(entry);
    final p = (await store.installed()).single;
    expect(p.manifest.id, 'demo');
    expect(p.source, fixture('demo.js'));
    expect(p.origin, repo);
  });

  test('install without a sha256 in the index still works', () async {
    await store.setRepos([repo]);
    final entry = (await m.available()).plugins.last.entry;
    expect(entry.sha256, isNull);
    await m.install(entry);
    expect((await store.installed()).single.manifest.id, 'nohash');
  });

  test('install refuses a tampered file', () async {
    await store.setRepos([repo]);
    final entry = (await m.available()).plugins.first.entry;
    http.overrides['https://repo.test/demo.js'] = (status: 200, body: 'evil()');
    await expectLater(
      m.install(entry),
      throwsA(
        isA<PluginException>()
            .having((e) => e.pluginId, 'id', 'demo')
            .having((e) => e.message, 'm', contains('sha256 mismatch')),
      ),
    );
    expect(await store.installed(), isEmpty);
  });

  test('install reports http failures, empty and oversize files', () async {
    await store.setRepos([repo]);
    final entry = (await m.available()).plugins.last.entry;
    const url = 'https://repo.test/demo.js';
    http.overrides[url] = (status: 500, body: '');
    await expectLater(m.install(entry), throwsA(isA<PluginException>()));
    http.overrides[url] = (status: 200, body: '');
    await expectLater(m.install(entry), throwsA(isA<PluginException>()));
    http.overrides[url] = (status: 200, body: 'x' * (kMaxPluginBytes + 1));
    await expectLater(m.install(entry), throwsA(isA<PluginException>()));
    http.overrides.clear();
    http.failWith = Exception('offline');
    await expectLater(
      m.install(entry),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'm',
          contains('download failed'),
        ),
      ),
    );
  });

  test(
    'installLocal and uninstall drive watchInstalled and clear prefs',
    () async {
      final seen = <List<String>>[];
      final sub = m.watchInstalled().listen(
        (l) => seen.add([for (final p in l) p.manifest.id]),
      );
      await pumpEventQueue();
      const manifest = PluginManifest(
        id: 'conv',
        name: 'Converted',
        version: '1',
        lang: 'en',
        baseUrl: 'https://c.test',
      );
      await m.installLocal(
        manifest,
        'function popular(){}',
        origin: 'mangayomi',
      );
      await pumpEventQueue();
      await store.prefSet('conv', 'k', 'v');
      await m.uninstall('conv');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [
        <String>[],
        ['conv'],
        <String>[],
      ]);
      expect(
        (await kv.entries()).keys.where((k) => k.contains('conv')),
        isEmpty,
      );
    },
  );

  test('installPlugin adds the repo and installs the offered id', () async {
    await m.installPlugin(repo: ' $repo ', id: 'demo');
    expect(await m.repos(), [repo]);
    expect([for (final p in await store.installed()) p.manifest.id], ['demo']);
  });

  test('installPlugin names the repo error, else "not offered"', () async {
    await expectLater(
      m.installPlugin(repo: repo, id: 'nope'),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          'not offered by its repo',
        ),
      ),
    );
    http.failWith = Exception('repo down');
    await expectLater(
      m.installPlugin(repo: repo, id: 'demo'),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          contains('repo down'),
        ),
      ),
    );
    expect(await store.installed(), isEmpty);
  });

  test('watchInstalled surfaces store errors on the stream', () async {
    await kv.set('plugins.installed.x', 'not json');
    await expectLater(m.watchInstalled(), emitsError(isA<FormatException>()));
  });
}
