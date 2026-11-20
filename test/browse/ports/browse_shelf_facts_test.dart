import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/ports/browse_shelf_facts.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/models/models.dart';

import '../fakes.dart';

void main() {
  final key = mangaKeyOf('mangadex', '/m/1');
  final early = DateTime.utc(2024, 6, 20);
  final late = DateTime.utc(2024, 6, 26);

  test('null until stored; then newest upload and all-read', () async {
    final src = FakeSource(
      'mangadex',
      chapters: [
        ChapterInfo(url: '/c/2', name: 'Ch. 2', number: 2, uploadedAt: early),
        ChapterInfo(url: '/c/3', name: 'Ch. 3', number: 3, uploadedAt: late),
        const ChapterInfo(url: '/c/1', name: 'Ch. 1', number: 1),
      ],
    );
    final store = ChapterStore((_) => src);
    final progress = FakeProgress();
    final facts = BrowseShelfFacts(store, progress);
    expect(await facts.of(key), isNull);
    expect(src.calls, isEmpty);
    await store.load(key);
    expect(await facts.of(key), (newestUpload: late, allRead: false));
    await progress.markReadMany(key, ['/c/1', '/c/2', '/c/3']);
    expect(await facts.of(key), (newestUpload: late, allRead: true));
  });

  test('no dated chapter: newest is null', () async {
    final store = ChapterStore((_) => FakeSource('mangadex'));
    await store.load(key);
    final facts = BrowseShelfFacts(store, FakeProgress());
    expect(await facts.of(key), (newestUpload: null, allRead: false));
  });
}
