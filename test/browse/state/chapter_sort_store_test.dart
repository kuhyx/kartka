import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/chapter_sort_store.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

void main() {
  const key = ChapterSortStore.storageKey;

  test('defaults to newest first (unreadFirst off)', () async {
    final store = ChapterSortStore(MemoryKeyValueStore());
    await store.ready;
    expect(store.value, isFalse);
  });

  test('set persists globally and a fresh store reads it back', () async {
    final kv = MemoryKeyValueStore();
    final store = ChapterSortStore(kv);
    await store.set(unreadFirst: true);
    expect(store.value, isTrue);
    expect(await kv.get(key), 'true');
    final fresh = ChapterSortStore(kv);
    await fresh.ready;
    expect(fresh.value, isTrue);
    await fresh.set(unreadFirst: false);
    expect(await kv.get(key), 'false');
  });

  test('a corrupt value reads as off', () async {
    final store = ChapterSortStore(MemoryKeyValueStore({key: 'yes'}));
    await store.ready;
    expect(store.value, isFalse);
  });

  test('reloads when a peer changed the key', () async {
    final kv = MemoryKeyValueStore();
    final changes = StreamController<String>();
    final store = ChapterSortStore(kv, reloadOn: changes.stream);
    await store.ready;
    await kv.set(key, 'true');
    changes
      ..add('other.key')
      ..add(key);
    await Future<void>.delayed(Duration.zero);
    expect(store.value, isTrue);
    await changes.close();
  });

  test('without a store it keeps the choice in memory only', () async {
    final store = ChapterSortStore(null);
    await store.set(unreadFirst: true);
    expect(store.value, isTrue);
  });
}
