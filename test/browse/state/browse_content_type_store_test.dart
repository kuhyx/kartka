import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/browse_content_type_store.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/settings/settings_catalog.dart';

void main() {
  const key = BrowseContentTypeStore.storageKey;

  test('unset means manga only', () async {
    final store = BrowseContentTypeStore(MemoryKeyValueStore());
    await store.ready;
    expect(store.value, ContentType.manga);
  });

  test('cycle persists the name and round-trips', () async {
    final kv = MemoryKeyValueStore();
    final store = BrowseContentTypeStore(kv);
    await store.cycle();
    expect(store.value, ContentType.mangaManhwa);
    expect(await kv.get(key), 'mangaManhwa');
    final again = BrowseContentTypeStore(kv);
    await again.ready;
    expect(again.value, ContentType.mangaManhwa);
    await again.cycle();
    await again.cycle();
    expect(again.value, ContentType.manga);
  });

  test('a corrupt value keeps the default', () async {
    final kv = MemoryKeyValueStore();
    await kv.set(key, 'webtoon');
    final store = BrowseContentTypeStore(kv);
    await store.ready;
    expect(store.value, ContentType.manga);
  });

  test("a peer's change reloads", () async {
    final kv = MemoryKeyValueStore();
    final changes = StreamController<String>();
    final store = BrowseContentTypeStore(kv, reloadOn: changes.stream);
    await store.ready;
    await kv.set(key, 'all');
    changes
      ..add('browse.languages')
      ..add(key);
    await pumpEventQueue();
    expect(store.value, ContentType.all);
    await changes.close();
  });

  test('without a store the choice lives in memory', () async {
    final store = BrowseContentTypeStore(null);
    await store.cycle();
    expect(store.value, ContentType.mangaManhwa);
  });

  test('the setting syncs as plain text', () {
    expect(kSyncedSettings[key]?.semanticLabel, 'Browse content type');
  });
}
