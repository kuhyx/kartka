import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/caching_key_value_store.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

/// Counts backend calls; [failNext] makes the next get/set/remove throw.
class _CountingStore extends MemoryKeyValueStore {
  int gets = 0;
  int entryCalls = 0;
  bool failNext = false;

  void _maybeFail() {
    if (!failNext) return;
    failNext = false;
    throw StateError('backend down');
  }

  @override
  Future<String?> get(String key) async {
    gets++;
    _maybeFail();
    return await super.get(key);
  }

  @override
  Future<void> set(String key, String value) async {
    _maybeFail();
    await super.set(key, value);
  }

  @override
  Future<void> remove(String key) async {
    _maybeFail();
    await super.remove(key);
  }

  @override
  Future<Map<String, String>> entries({String prefix = ''}) {
    entryCalls++;
    return super.entries(prefix: prefix);
  }
}

void main() {
  const key = 'tracking.anilist.token';
  late _CountingStore backend;
  late CachingKeyValueStore store;

  setUp(() {
    backend = _CountingStore();
    store = CachingKeyValueStore(backend);
  });

  test('N reads of an absent key hit the backend once', () async {
    for (var i = 0; i < 48; i++) {
      expect(await store.get(key), isNull);
    }
    expect(backend.gets, 1);
  });

  test('concurrent reads share one backend read', () async {
    await backend.set(key, 'v');
    final all = await Future.wait([
      for (var i = 0; i < 10; i++) store.get(key),
    ]);
    expect(all, everyElement('v'));
    expect(backend.gets, 1);
  });

  test('a write then a read returns the fresh value', () async {
    expect(await store.get(key), isNull);
    await store.set(key, 'fresh');
    expect(await store.get(key), 'fresh');
    expect(backend.gets, 1);
    expect(await backend.get(key), 'fresh');
  });

  test('a remove then a read returns null without a backend read', () async {
    await backend.set(key, 'old');
    expect(await store.get(key), 'old');
    await store.remove(key);
    expect(await store.get(key), isNull);
    expect(backend.gets, 1);
  });

  test('a failed read is not cached', () async {
    backend.failNext = true;
    await expectLater(store.get(key), throwsStateError);
    expect(await store.get(key), isNull);
    expect(backend.gets, 2);
  });

  test('a failed write drops the cached value', () async {
    await store.set(key, 'a');
    backend.failNext = true;
    await expectLater(store.set(key, 'b'), throwsStateError);
    expect(await store.get(key), 'a');
    expect(backend.gets, 1);
  });

  test('a failed remove drops the cached value', () async {
    await store.set(key, 'a');
    backend.failNext = true;
    await expectLater(store.remove(key), throwsStateError);
    expect(await store.get(key), 'a');
    expect(backend.gets, 1);
  });

  test('a write wins over a read still in flight', () async {
    await backend.set(key, 'old');
    final read = store.get(key);
    await store.set(key, 'new');
    expect(await read, 'old');
    expect(await store.get(key), 'new');
    expect(backend.gets, 1);
  });

  test('entries passes through to the backend', () async {
    await store.set('a.x', '1');
    await store.set('b.y', '2');
    expect(await store.entries(prefix: 'a.'), {'a.x': '1'});
    expect(backend.entryCalls, 1);
  });
}
