import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/chapter_list_decoder.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

String _stored(int n) => jsonEncode([
  for (var i = 0; i < n; i++)
    ChapterInfo(url: '/c$i', name: 'Chapter $i', number: i.toDouble()).toJson(),
]);

/// Holds every read until [gate] completes.
class _GatedKv extends MemoryKeyValueStore {
  new(super.seed);
  final gate = Completer<void>();

  @override
  Future<String?> get(String key) async {
    await gate.future;
    return await super.get(key);
  }
}

void main() {
  final src = FakeSource('mangadex');
  MangaKey key(int i) => mangaKeyOf('mangadex', '/m/$i');

  test('restoring N stored lists decodes them in one batch', () async {
    final decoder = ChapterListDecoder();
    final texts = [for (var i = 0; i < 30; i++) _stored(i + 1)];
    final lists = await Future.wait(texts.map(decoder.decode));
    expect(
      [for (final l in lists) l!.length],
      [for (var i = 1; i <= 30; i++) i],
    );
    expect(decoder.batches, 1, reason: 'one decode pass for the burst');
    await decoder.decode(_stored(2));
    expect(decoder.batches, 2);
  });

  test('a large burst decodes off the UI isolate, corrupt rows as null', () {
    final big = _stored(2000);
    expect(big.length, greaterThan(chapterDecodeOffUiChars));
    expect(decodeChapterLists([big, '{bad', '[1]']), [
      hasLength(2000),
      null,
      null,
    ]);
    final decoder = ChapterListDecoder();
    expect(decoder.decode(big), completion(hasLength(2000)));
    expect(decoder.decode('{bad'), completion(isNull));
  });

  test('N library watchers restore every stored list (badges stay)', () async {
    final kv = MemoryKeyValueStore({
      for (var i = 0; i < 40; i++)
        'browse.chapters.${mangaKeyHash(key(i))}': _stored(3),
    });
    final store = ChapterStore((id) => src, kv: kv);
    final seen = <MangaKey, int?>{};
    final subs = [
      for (var i = 0; i < 40; i++)
        store.watch(key(i)).listen((l) => seen[key(i)] = l?.length),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(seen.values.toSet(), {3});
    expect(seen, hasLength(40));
    for (final s in subs) {
      unawaited(s.cancel());
    }
  });

  test('a fetch that lands during a restore is not overwritten', () async {
    final kv = _GatedKv({
      'browse.chapters.${mangaKeyHash(key(1))}': _stored(1),
    });
    final store = ChapterStore((id) => src, kv: kv);
    final restoring = store.stored(key(1));
    final fresh = await store.load(key(1), refresh: true);
    kv.gate.complete();
    expect(await restoring, same(fresh));
    expect(store.cached(key(1)), same(fresh));
  });
}
