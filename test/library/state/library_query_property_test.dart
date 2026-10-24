import 'package:glados/glados.dart';
import 'package:kartka/library/state/library_item.dart';
import 'package:kartka/library/state/library_query.dart';

extension on Any {
  Generator<LibraryItem> get libraryItem => combine7(
    intInRange(0, 40),
    choose(['Akira', 'akira', 'Berserk', 'Monster', 'Pluto', '']),
    intInRange(0, 5),
    intInRange(-1, 5),
    intInRange(-1, 4),
    combine2(this.bool, this.bool, (d, t) => (d, t)),
    choose(<Set<String>>[
      {},
      {'x'},
      {'y'},
      {'x', 'y'},
    ]),
    (k, title, added, read, unread, dt, cats) {
      return LibraryItem(
        key: 'k$k',
        sourceId: 's',
        mangaUrl: '/$k',
        title: title,
        addedAt: DateTime.utc(2026, 1, 1 + added),
        lastReadAt: read < 0 ? null : DateTime.utc(2026, 2, 1 + read),
        unread: unread < 0 ? null : unread,
        downloaded: dt.$1,
        tracked: dt.$2,
        categoryIds: cats,
      );
    },
  );

  /// Unique keys: the library never holds the same MangaKey twice.
  Generator<List<LibraryItem>> get library =>
      list(libraryItem)
          .map((items) => {for (final i in items) i.key: i}.values.toList());

  Generator<LibraryQuery> get libraryQuery => combine5(
    choose(LibrarySort.values),
    this.bool,
    combine3(this.bool, this.bool, this.bool, (u, d, t) => (u, d, t)),
    choose(<String?>[null, 'x', 'y']),
    choose(['', 'ak', 'ER', 'zz']),
    (sort, asc, f, cat, s) => LibraryQuery(
      sort: sort,
      ascending: asc,
      unreadOnly: f.$1,
      downloadedOnly: f.$2,
      trackedOnly: f.$3,
      categoryId: cat,
      search: s,
    ),
  );
}

final _explore = ExploreConfig(numRuns: 200);

void main() {
  Glados2(any.library, any.libraryQuery, _explore).test(
    'idempotent: applying a query twice changes nothing',
    (items, q) {
      final once = applyQuery(items, q);
      expect(applyQuery(once, q), once);
    },
  );

  Glados2(any.library, any.libraryQuery, _explore).test(
    'order-independent: input order never changes the output',
    (items, q) {
      expect(applyQuery(items.reversed.toList(), q), applyQuery(items, q));
    },
  );

  Glados2(any.library, any.libraryQuery, _explore).test(
    'subset: every result is an input item that satisfies every filter',
    (items, q) {
      final out = applyQuery(items, q);
      expect(out.toSet().length, out.length);
      for (final i in out) {
        expect(items, contains(i));
        expect(q.matches(i), isTrue);
      }
      final dropped = items.where((i) => !out.contains(i));
      expect(dropped.every((i) => !q.matches(i)), isTrue);
    },
  );

  Glados2(any.library, any.libraryQuery, _explore).test(
    'sorted: neighbours are in comparator order',
    (items, q) {
      final out = applyQuery(items, q);
      for (var n = 1; n < out.length; n++) {
        expect(q.compare(out[n - 1], out[n]), lessThan(0));
      }
    },
  );
}
