import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';

void main() {
  late MemoryKeyValueStore kv;
  setUp(() => kv = MemoryKeyValueStore());

  test('empty storage keeps defaults', () async {
    final store = MangadexSettingsStore(kv);
    await store.ready;
    expect(store.value, MangadexSettings.defaults);
  });

  test('save persists and a new store loads it', () async {
    final s = MangadexSettings.defaults.copyWith(
      languages: ['pl'],
      dataSaver: true,
    );
    await MangadexSettingsStore(kv).save(s);
    expect(await kv.get(MangadexSettingsStore.storageKey), isNotNull);
    final again = MangadexSettingsStore(kv);
    await again.ready;
    expect(again.value, s);
  });

  test('save notifies listeners', () async {
    final store = MangadexSettingsStore(kv);
    var calls = 0;
    store.addListener(() => calls++);
    await store.save(MangadexSettings.defaults.copyWith(dataSaver: true));
    expect(calls, 1);
  });

  test('corrupt or non-object JSON keeps defaults', () async {
    for (final raw in ['{not json', '[1,2]']) {
      await kv.set(MangadexSettingsStore.storageKey, raw);
      final store = MangadexSettingsStore(kv);
      await store.ready;
      expect(store.value, MangadexSettings.defaults);
    }
  });
}
