import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source_provider.dart';

import 'fakes.dart';

void main() {
  late SuwayomiSettingsStore store;
  setUp(
    () => store = SuwayomiSettingsStore(
      kv: MemoryKeyValueStore(),
      secrets: MemoryKeyValueStore(),
    ),
  );

  // Disposed after each test: a failed fetch leaves a retry timer.
  SuwayomiSourceProvider provider(KartkaHttp http) {
    final p = SuwayomiSourceProvider(
      store: store,
      client: SuwayomiClient(
        http: http,
        settings: () => store.current ?? const SuwayomiSettings(),
      ),
    );
    addTearDown(p.dispose);
    return p;
  }

  List<String> ids(List<MangaSource> s) => [for (final x in s) x.ref.id];

  test("lists every installed source except Suwayomi's local one", () async {
    await store.save(fixtureSettings);
    final p = provider(fixtureHttp(['sources']));
    final sources = await p.watch().first;
    expect(ids(sources), [
      'suwayomi:1411768577036936240',
      'suwayomi:$mangadexEn',
    ]);
    expect(sources.last.ref.lang, 'en');
    // A second watcher gets the cached list without another request.
    expect(ids(await p.watch().first), ids(sources));
    await p.dispose();
  });

  test('is empty while unconfigured and while the server is down', () async {
    expect(await provider(fixtureHttp([])).watch().first, isEmpty);
    await store.save(fixtureSettings);
    expect(await provider(cannedHttp(502, '')).watch().first, isEmpty);
  });

  test('re-lists after the settings change and on refresh', () async {
    final http = fixtureHttp(['sources']);
    final p = provider(http);
    final emitted = <int>[];
    final sub = p.watch().listen((s) => emitted.add(s.length));
    await pumpEventQueue();
    await store.save(fixtureSettings);
    await pumpEventQueue();
    await p.refresh();
    await pumpEventQueue();
    expect(emitted, [0, 2, 2]);
    await sub.cancel();
    await p.dispose();
  });

  test('sends basic auth only to the configured server', () async {
    final p = provider(fixtureHttp([]));
    expect(p.forUrl('http://127.0.0.1:4599/api/v1/manga/1/thumbnail'), isEmpty);
    await store.save(fixtureSettings);
    expect(
      p.forUrl('http://127.0.0.1:4599/api/v1/manga/1/thumbnail'),
      fixtureSettings.authHeaders,
    );
    expect(p.forUrl('https://uploads.mangadex.org/x.jpg'), isEmpty);
  });
}
