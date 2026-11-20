import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/ports/browse_dupe_facts.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/browse/state/detail_store.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../fakes.dart';

void main() {
  final key = mangaKeyOf('mangadex', '/m/1');

  test('null until stored; then details, chapters and read urls', () async {
    final src = FakeSource(
      'mangadex',
      chapters: const [
        ChapterInfo(url: '/c/2', name: 'Ch. 2', number: 2),
        ChapterInfo(url: '/c/1', name: 'Ch. 1', number: 1),
      ],
    );
    final store = ChapterStore((_) => src);
    final details = DetailStore(MemoryKeyValueStore());
    final progress = FakeProgress();
    final facts = BrowseDupeFacts(store, details, progress);
    expect(await facts.of(key), isNull);
    expect(src.calls, isEmpty);
    await store.load(key);
    await progress.markReadMany(key, ['/c/1']);
    var f = (await facts.of(key))!;
    expect((f.details, f.chapters.length), (null, 2));
    expect(f.readUrls, {'/c/1'});
    const d = MangaDetails(
      sourceId: 'mangadex',
      url: '/m/1',
      title: 'Dream',
      authors: ['Kirihara Idumi'],
    );
    await details.write(key, d);
    f = (await facts.of(key))!;
    expect(f.details?.authors, ['Kirihara Idumi']);
  });
}
