import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';

/// Ch.12 (MM), Ch.11 by two groups, Ch.10, newest first.
const _chapters = [
  ChapterInfo(url: '/mm12', name: 'Ch. 12', number: 12, scanlator: 'MM'),
  ChapterInfo(url: '/hy11', name: 'Ch. 11: x', number: 11, scanlator: 'Hy'),
  ChapterInfo(url: '/mm11', name: 'Ch. 11', number: 11, scanlator: 'MM'),
  ChapterInfo(url: '/mm10', name: 'Ch. 10', number: 10, scanlator: 'MM'),
];

void main() {
  late LocalProgressRepository progress;

  ReaderSession make(String chapter) {
    final source = FakeSource(
      chapterList: _chapters,
      pageMap: {for (final c in _chapters) c.url: fakePages(c.url, 3)},
    );
    return ReaderSession(
      sourceId: 'fake',
      mangaUrl: '/m/1',
      chapterUrl: chapter,
      deps: ReaderDeps(
        findSource: (id) async => source,
        progress: progress,
        prefs: ReaderPrefs(MemoryKeyValueStore()),
        loadImage: (p) async => Uint8List(1),
        now: () => DateTime.utc(2026, 10, 29),
      ),
    );
  }

  ReadingProgress at(String url, double number, int page) => ReadingProgress(
    key: mangaKeyOf('fake', '/m/1'),
    chapterUrl: url,
    chapterNumber: number,
    page: page,
    readAt: DateTime.utc(2026, 10, 28),
  );

  setUp(() => progress = LocalProgressRepository(MemoryKeyValueStore()));

  Future<ReadingProgress?> saved() =>
      progress.watch(mangaKeyOf('fake', '/m/1')).first;

  test('reading on from Ch.11 of one group lands on Ch.12', () async {
    final s = make('/mm11');
    await s.open();
    expect(s.nextChapter?.url, '/mm12');
    s.onItem(2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.segments.map((x) => x.url), ['/mm11', '/mm12']);
    for (var item = 3; item <= 6; item++) {
      s.onItem(item);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    final p = await saved();
    expect(p?.chapterUrl, '/mm12');
    expect(p?.chapterNumber, 12);
    s.dispose();
  });

  test('entering a same-number copy never moves Continue back', () async {
    await progress.record(at('/mm11', 11, 2));
    final s = make('/hy11');
    await s.open();
    s.onItem(0);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect((await saved())?.chapterUrl, '/mm11');
    // Read through Ch.12: a duplicate Ch.11 cannot win Continue back.
    await progress.record(at('/mm12', 12, 0));
    s.onItem(1);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect((await saved())?.chapterUrl, '/mm12');
    s.dispose();
  });
}
