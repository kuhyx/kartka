import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source_provider.dart';

import 'fakes.dart';

/// A Keystore that fails every read (Android Keystore errors are real).
class _BrokenSecrets extends MemoryKeyValueStore {
  @override
  Future<String?> get(String key) async => throw StateError('keystore');
}

/// Every source list must arrive (even empty) on subscribe, or the
/// library's "unavailable source" badges stay hidden forever.
void main() {
  late SuwayomiSettingsStore store;
  setUp(
    () => store = SuwayomiSettingsStore(
      kv: MemoryKeyValueStore(),
      secrets: MemoryKeyValueStore(),
    ),
  );

  SuwayomiSourceProvider provider(KartkaHttp http, [KeyValueStore? secrets]) {
    final s = secrets == null
        ? store
        : store = SuwayomiSettingsStore(
            kv: MemoryKeyValueStore(),
            secrets: secrets,
          );
    final p = SuwayomiSourceProvider(
      store: s,
      client: SuwayomiClient(
        http: http,
        settings: () => s.current ?? const SuwayomiSettings(),
      ),
    );
    addTearDown(p.dispose); // a failed fetch leaves a retry timer
    return p;
  }

  Future<List<MangaSource>> first(SuwayomiSourceProvider p) =>
      p.watch().first.timeout(const Duration(seconds: 2));

  test('emits [] when the HTTP layer throws an Error', () async {
    await store.save(fixtureSettings);
    final p = provider(FakeKartkaHttp((_) => throw ArgumentError('bad url')));
    expect(await first(p), isEmpty);
  });

  test('emits [] when the server answers an unexpected shape', () async {
    await store.save(fixtureSettings);
    final p = provider(cannedHttp(200, '{"data":{"sources":null}}'));
    expect(await first(p), isEmpty);
  });

  test('emits [] when the settings cannot be read', () async {
    final p = provider(fixtureHttp(['sources']), _BrokenSecrets());
    expect(await first(p), isEmpty);
  });

  test('refresh after a failure does not throw', () async {
    await store.save(fixtureSettings);
    final p = provider(cannedHttp(200, '{"data":{}}'));
    final emitted = <int>[];
    final sub = p.watch().listen((s) => emitted.add(s.length));
    await pumpEventQueue();
    await p.refresh();
    await pumpEventQueue();
    expect(emitted, [0, 0]);
    await sub.cancel();
    await p.dispose();
  });
}
