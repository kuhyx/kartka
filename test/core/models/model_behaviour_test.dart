import 'package:glados/glados.dart';
import 'package:kartka/core/models/models.dart';

import '../../helpers/generators.dart';

ReadingProgress _at(double chapter, int page) => ReadingProgress(
  key: 'k',
  chapterUrl: 'c',
  chapterNumber: chapter,
  page: page,
  readAt: DateTime.utc(2026),
);

void main() {
  group('keys', () {
    test('mangaKeyOf joins with a pipe', () {
      expect(mangaKeyOf('mangadex', '/title/1'), 'mangadex|/title/1');
      const m = MangaSummary(sourceId: 's', url: 'u', title: 't');
      expect(m.key, 's|u');
    });
    test('mangaKeyHash is lowercase hex SHA-1 of UTF-8', () {
      // printf 'abc' | sha1sum
      expect(mangaKeyHash('abc'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
      expect(mangaKeyHash('ż'), hasLength(40));
    });
  });

  group('ReadingProgress.isAheadOf', () {
    test('orders by chapter, then page; anything beats null', () {
      expect(_at(1, 0).isAheadOf(null), isTrue);
      expect(_at(2, 0).isAheadOf(_at(1, 9)), isTrue);
      expect(_at(1, 9).isAheadOf(_at(2, 0)), isFalse);
      expect(_at(1, 3).isAheadOf(_at(1, 2)), isTrue);
      expect(_at(1, 2).isAheadOf(_at(1, 2)), isFalse);
    });
    Glados2(any.readingProgress, any.readingProgress).test(
      'is a strict order: irreflexive and asymmetric',
      (a, b) {
        expect(a.isAheadOf(a), isFalse);
        expect(a.isAheadOf(b) && b.isAheadOf(a), isFalse);
      },
    );
  });

  group('JSON decoding tolerance', () {
    test('integral numbers decode as doubles (web JSON)', () {
      final p = ReadingProgress.fromJson({
        'key': 'k',
        'chapterUrl': 'c',
        'chapterNumber': 3,
        'page': 2.0,
        'readAt': '2026-01-01T00:00:00.000Z',
      });
      expect(p.chapterNumber, 3.0);
      expect(p.page, 2);
      final c = ChapterInfo.fromJson({'url': 'u', 'name': 'n', 'number': 7});
      expect(c.number, 7.0);
    });
    test('absent optional fields take their defaults', () {
      final d = MangaDetails.fromJson({
        'sourceId': 's',
        'url': 'u',
        'title': 't',
      });
      expect(d.authors, isEmpty);
      expect(d.genres, isEmpty);
      expect(d.trackerIds, isEmpty);
      expect(d.status, MangaStatus.unknown);
      expect(PageRef.fromJson({'index': 0, 'imageUrl': 'x'}).headers, isEmpty);
      final cat = Category.fromJson({
        'id': 'i',
        'name': 'n',
        'order': 1,
        'updatedAt': '2026-01-01T00:00:00Z',
      });
      expect(cat.removed, isFalse);
      expect(SearchPage.fromJson({'items': <Object?>[]}), SearchPage.empty);
    });
    test('decoded collections are unmodifiable', () {
      final d = MangaDetails.fromJson({
        'sourceId': 's',
        'url': 'u',
        'title': 't',
        'genres': ['a'],
      });
      expect(() => d.genres.add('b'), throwsUnsupportedError);
    });
  });

  group('equality', () {
    test('instants compare by moment, not time zone', () {
      final utc = DateTime.utc(2026, 1, 1, 12);
      final local = utc.toLocal();
      expect(_withDate(utc), _withDate(local));
      expect(_withDate(utc).hashCode, _withDate(local).hashCode);
    });
    test('details never equal a plain summary', () {
      const s = MangaSummary(sourceId: 's', url: 'u', title: 't');
      const d = MangaDetails(sourceId: 's', url: 'u', title: 't');
      expect(s == d, isFalse);
      expect(d == s, isFalse);
      expect(s.toString(), 'MangaSummary(s|u)');
      expect(d.toString(), 'MangaDetails(s|u)');
    });
    test('toString names the value', () {
      expect(_withDate(DateTime.utc(2026)).toString(), 'Category(c, n)');
      expect(_entry(removed: true).toString(), contains('removed'));
      expect(_entry().toString(), 'LibraryEntry(s|u)');
    });
  });

  group('LibraryEntry.copyWith', () {
    test('replaces only the given fields', () {
      final e = _entry();
      final later = DateTime.utc(2027);
      final c = e.copyWith(title: 'T2', updatedAt: later, removed: true);
      expect(c.title, 'T2');
      expect(c.updatedAt, later);
      expect(c.removed, isTrue);
      expect(c.addedAt, e.addedAt);
      expect(c.coverUrl, e.coverUrl);
      expect(e.copyWith(coverUrl: 'x').coverUrl, 'x');
      expect(e.copyWith(), e);
    });
  });

  group('DownloadState', () {
    test('fraction is 0 until the page count is known, then clamped', () {
      expect(DownloadState.none.fraction, 0);
      const half = DownloadState(
        status: DownloadStatus.downloading,
        pagesDone: 5,
        pagesTotal: 10,
      );
      expect(half.fraction, 0.5);
      const over = DownloadState(
        status: DownloadStatus.done,
        pagesDone: 12,
        pagesTotal: 10,
      );
      expect(over.fraction, 1);
    });
  });

  test('MangaStatus follows Tachiyomi codes 0-6', () {
    expect(MangaStatus.values[2], MangaStatus.completed);
    expect(MangaStatus.values[6], MangaStatus.onHiatus);
  });
}

Category _withDate(DateTime at) =>
    Category(id: 'c', name: 'n', order: 0, updatedAt: at);

LibraryEntry _entry({bool removed = false}) => LibraryEntry(
  key: 's|u',
  sourceId: 's',
  mangaUrl: 'u',
  title: 't',
  coverUrl: 'cov',
  addedAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2026),
  removed: removed,
);
