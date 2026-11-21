import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/browse_content_type_store.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/settings/settings_catalog.dart';

void main() {
  const key = BrowseContentTypeStore.storageKey;

  test('unset means every type ticked', () async {
    final store = BrowseContentTypeStore(MemoryKeyValueStore());
    await store.ready;
    expect(store.value, ContentTypes.all);
  });

  test('toggle persists the ticked list and round-trips', () async {
    final kv = MemoryKeyValueStore();
    final store = BrowseContentTypeStore(kv);
    await store.toggle(ContentType.manhua);
    expect(store.value.toJson(), ['manga', 'manhwa']);
    expect(await kv.get(key), '["manga","manhwa"]');
    final again = BrowseContentTypeStore(kv);
    await again.ready;
    expect(again.value, store.value);
    await again.toggle(ContentType.manga);
    await again.toggle(ContentType.manhwa);
    expect(again.value, ContentTypes.none);
    expect(await kv.get(key), '[]');
  });

  test('an old single choice reads as its ticked set', () async {
    final kv = MemoryKeyValueStore();
    for (final (old, ticked) in [
      ('manga', ['manga']),
      ('mangaManhwa', ['manga', 'manhwa']),
      ('all', ['manga', 'manhwa', 'manhua']),
    ]) {
      await kv.set(key, old);
      final store = BrowseContentTypeStore(kv);
      await store.ready;
      expect(store.value.toJson(), ticked, reason: old);
    }
  });

  test('a corrupt value keeps the default', () async {
    final kv = MemoryKeyValueStore();
    await kv.set(key, 'webtoon');
    final store = BrowseContentTypeStore(kv);
    await store.ready;
    expect(store.value, ContentTypes.all);
  });

  test("a peer's change reloads", () async {
    final kv = MemoryKeyValueStore();
    final changes = StreamController<String>();
    final store = BrowseContentTypeStore(kv, reloadOn: changes.stream);
    await store.ready;
    await kv.set(key, '["manhua"]');
    changes
      ..add('browse.languages')
      ..add(key);
    await pumpEventQueue();
    expect(store.value.toJson(), ['manhua']);
    await changes.close();
  });

  test('without a store the choice lives in memory', () async {
    final store = BrowseContentTypeStore(null);
    await store.toggle(ContentType.manga);
    expect(store.value.toJson(), ['manhwa', 'manhua']);
  });

  test('the setting syncs as plain text', () {
    expect(kSyncedSettings[key]?.semanticLabel, 'Browse content type');
  });
}
