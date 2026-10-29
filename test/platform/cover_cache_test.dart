import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/cover_cache.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/platform/platform.dart';

const _url = 'https://img.test/cover.jpg';

/// [tag]'s bytes behind a PNG signature, so the cache takes them as an image.
Uint8List _png(String tag) =>
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...utf8.encode(tag)]);

String _key(String url) => 'cache/covers/${sha1.convert(utf8.encode(url))}';

/// A store whose every call throws (a full disk, a wrapper that is down).
class _BrokenStore implements BlobStore {
  @override
  Future<void> put(String key, Uint8List bytes) async =>
      throw StateError('disk full');

  @override
  Future<Uint8List?> get(String key) async => throw StateError('io');

  @override
  Future<void> delete(String key) async {}

  @override
  Future<List<String>> list(String prefix) async => const [];
}

void main() {
  late List<String> loads;
  late Map<String, Completer<Uint8List>> gates;

  Future<Uint8List> load(String url) async {
    loads.add(url);
    final gate = gates[url];
    if (gate != null) return await gate.future;
    return _png(url);
  }

  setUp(() {
    loads = [];
    gates = {};
  });

  test('concurrent requests share one load; then memory answers', () async {
    final store = MemoryBlobStore();
    final cache = CoverCache(load: load, store: store);
    gates[_url] = Completer();
    expect(cache.peek(_url), isNull);
    final a = cache.get(_url);
    final b = cache.get(_url);
    gates[_url]!.complete(_png('7'));
    final bytes = await a;
    expect(await b, same(bytes));
    expect(loads, [_url]);
    expect(cache.peek(_url), same(bytes));
    // A memory hit completes synchronously: no placeholder frame.
    Uint8List? sync;
    unawaited(cache.get(_url).then((v) => sync = v));
    expect(sync, same(bytes));
    await pumpEventQueue();
    expect(await store.get(_key(_url)), _png('7'));
  });

  test('a later launch reads the persistent store, not the network', () async {
    final store = MemoryBlobStore();
    await CoverCache(load: load, store: store).get(_url);
    await pumpEventQueue();
    final next = CoverCache(load: load, store: store);
    expect(await next.get(_url), _png(_url));
    expect(loads, [_url]);
  });

  test('offline blob covers are kept in memory only', () async {
    final store = MemoryBlobStore();
    const blob = 'kartka-blob://covers/abc';
    final cache = CoverCache(load: load, store: store);
    await cache.get(blob);
    await pumpEventQueue();
    expect(await store.list(''), isEmpty);
    expect(cache.peek(blob), isNotNull);
  });

  test('a failed load is not cached; the next request retries', () async {
    final cache = CoverCache(load: load);
    gates[_url] = Completer();
    final failing = cache.get(_url);
    gates[_url]!.completeError(StateError('offline'));
    await expectLater(failing, throwsStateError);
    gates.remove(_url);
    expect(await cache.get(_url), _png(_url));
    expect(loads, [_url, _url]);
  });

  test('memory is bounded by bytes, oldest first', () async {
    final cache = CoverCache(load: load, maxBytes: 60);
    const a = 'https://img.test/aaaaaaaaaaaaaaaaaaaaa'; // 4 + 37 bytes
    const b = 'https://img.test/bbbbbbbbbbbb'; // 4 + 28 bytes
    await cache.get(a);
    await cache.get(b);
    expect(cache.peek(a), isNull);
    expect(cache.peek(b), isNotNull);
    // A hit refreshes recency.
    const c = 'https://img.test/c';
    await cache.get(c);
    expect(cache.peek(b), isNotNull);
    expect(cache.peek(c), isNotNull);
  });

  test('a failing store only costs the persistence', () async {
    final cache = CoverCache(load: load, store: _BrokenStore());
    expect(await cache.get(_url), _png(_url));
    await pumpEventQueue();
    expect(loads, [_url]);
  });

  test('only image bytes persist: a 200 challenge page is not kept', () async {
    final store = MemoryBlobStore();
    final cache = CoverCache(
      load: (_) async => Uint8List.fromList(utf8.encode('<html>')),
      store: store,
    );
    expect(utf8.decode(await cache.get(_url)), '<html>');
    await pumpEventQueue();
    expect(await store.list(''), isEmpty);
    for (final magic in [
      [0xFF, 0xD8, 0xFF, 0xE0],
      utf8.encode('GIF89a'),
      [...utf8.encode('RIFF'), 0, 0, 0, 0, ...utf8.encode('WEBP')],
      [0, 0, 0, 0x1C, ...utf8.encode('ftypavif')],
    ]) {
      expect(
        looksLikeImage(Uint8List.fromList(magic)),
        isTrue,
        reason: '$magic',
      );
    }
    expect(looksLikeImage(Uint8List(2)), isFalse);
  });
}
