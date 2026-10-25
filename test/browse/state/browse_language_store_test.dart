import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/language_filter.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

void main() {
  const key = BrowseLanguageStore.storageKey;

  test('the key is browse.languages', () {
    expect(key, 'browse.languages');
  });

  test('unset: the default selection, nothing written', () async {
    final kv = MemoryKeyValueStore();
    final store = BrowseLanguageStore(kv);
    await store.ready;
    expect(store.value, kDefaultBrowseLanguages);
    expect(await kv.get(key), isNull);
  });

  test('toggling on an unset value edits the default and persists', () async {
    final kv = MemoryKeyValueStore();
    final store = BrowseLanguageStore(kv);
    await store.toggle('pl');
    expect(store.value, ['en', kAllLanguages, 'ja', 'pl']);
    await store.toggle('en');
    expect(store.value, [kAllLanguages, 'ja', 'pl']);
    final fresh = BrowseLanguageStore(kv);
    await fresh.ready;
    expect(fresh.value, [kAllLanguages, 'ja', 'pl']);
  });

  test('unticking everything stores an empty selection', () async {
    final kv = MemoryKeyValueStore({
      key: jsonEncode(['en']),
    });
    final store = BrowseLanguageStore(kv);
    await store.toggle('EN');
    final fresh = BrowseLanguageStore(kv);
    await fresh.ready;
    expect(fresh.value, isEmpty);
  });

  test('stored codes are bucketed and de-duplicated on load', () async {
    final kv = MemoryKeyValueStore({
      key: jsonEncode(['multi', 'EN', 'all', 'en']),
    });
    final store = BrowseLanguageStore(kv);
    await store.ready;
    expect(store.value, [kAllLanguages, 'en']);
  });

  test('a corrupt or non-list value falls back to the default', () async {
    for (final raw in ['{nope', '{"a":1}', '[1,2]']) {
      final store = BrowseLanguageStore(MemoryKeyValueStore({key: raw}));
      await store.ready;
      expect(store.value, kDefaultBrowseLanguages, reason: raw);
    }
  });

  test('reloads when a peer changes the synced key', () async {
    final kv = MemoryKeyValueStore();
    final remote = StreamController<String>();
    final store = BrowseLanguageStore(kv, reloadOn: remote.stream);
    await store.ready;
    await kv.set(key, jsonEncode(['ko']));
    remote.add('reader.settings');
    await pumpEventQueue();
    expect(store.value, kDefaultBrowseLanguages);
    remote.add(key);
    await pumpEventQueue();
    expect(store.value, ['ko']);
    await kv.remove(key);
    remote.add(key);
    await pumpEventQueue();
    expect(store.value, kDefaultBrowseLanguages);
    await remote.close();
  });
}
