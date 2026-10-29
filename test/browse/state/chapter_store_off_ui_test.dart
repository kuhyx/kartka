import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/chapter_list_decoder.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

String _stored(int n) => jsonEncode([
  for (var i = 0; i < n; i++)
    ChapterInfo(url: '/c$i', name: 'Chapter $i', number: i.toDouble()).toJson(),
]);

/// A store that decodes by key, like the Android one: counts how its
/// values are reached. [gate] holds every `decodeAll` until completed.
class _KeyedKv extends MemoryKeyValueStore implements OffUiDecodingStore {
  new(super.seed);

  int gets = 0;
  final batches = <List<String>>[];
  Completer<void>? gate;
  bool failing = false;

  @override
  Future<String?> get(String key) {
    gets++;
    return super.get(key);
  }

  @override
  Future<List<R?>> decodeAll<R extends Object>(
    List<String> keys,
    R? Function(String text) decode,
  ) async {
    batches.add(keys);
    await gate?.future;
    if (failing) throw StateError('isolate died');
    return [
      for (final k in keys)
        if (await super.get(k) case final text?) decode(text) else null,
    ];
  }
}

void main() {
  final src = FakeSource('mangadex');
  MangaKey key(int i) => mangaKeyOf('mangadex', '/m/$i');
  String kvKey(int i) => 'browse.chapters.${mangaKeyHash(key(i))}';

  test('a cold start restores every list by key, in one batch', () async {
    final kv = _KeyedKv({for (var i = 0; i < 40; i++) kvKey(i): _stored(3)});
    kv.batches.clear();
    final store = ChapterStore((id) => src, kv: kv);
    final seen = <MangaKey, int?>{};
    final subs = [
      for (var i = 0; i < 40; i++)
        store.watch(key(i)).listen((l) => seen[key(i)] = l?.length),
    ];
    await pumpEventQueue();

    expect(seen.values.toSet(), {3});
    expect(seen, hasLength(40));
    // Before: 40 reads on the UI isolate, 40 strings copied to the decoder.
    expect(kv.gets, 0, reason: 'no value is read on the UI isolate');
    expect(kv.batches, hasLength(1));
    expect(kv.batches.single, hasLength(40));
    for (final s in subs) {
      await s.cancel();
    }
  });

  test('absent and corrupt entries restore as nothing', () async {
    final kv = _KeyedKv({kvKey(1): '{bad', kvKey(2): '[1]'});
    final store = ChapterStore((id) => src, kv: kv);
    expect(await store.stored(key(1)), isNull);
    expect(await store.stored(key(2)), isNull);
    expect(await store.stored(key(3)), isNull);
  });

  test(
    'a fetch that lands during a keyed restore is not overwritten',
    () async {
      final kv = _KeyedKv({kvKey(1): _stored(1)})..gate = Completer<void>();
      final store = ChapterStore((id) => src, kv: kv);
      final restoring = store.stored(key(1));
      final fresh = await store.load(key(1), refresh: true);
      kv.gate!.complete();
      expect(await restoring, same(fresh));
    },
  );

  test('an unreadable store restores as nothing, then fetches', () async {
    final kv = _KeyedKv({kvKey(1): _stored(2)})..failing = true;
    final store = ChapterStore((id) => src, kv: kv);
    expect(await store.stored(key(1)), isNull);
    expect(await store.load(key(1)), isNotEmpty, reason: 'fetched instead');
  });

  test('a store without keyed decoding still restores through get', () async {
    final kv = MemoryKeyValueStore({kvKey(1): _stored(2)});
    final store = ChapterStore((id) => src, kv: kv);
    expect(await store.stored(key(1)), hasLength(2));
    expect(await store.stored(key(9)), isNull);
  });

  test('decodeChapterList reads one stored list', () {
    expect(decodeChapterList(_stored(4)), hasLength(4));
    expect(decodeChapterList('{bad'), isNull);
  });
}
