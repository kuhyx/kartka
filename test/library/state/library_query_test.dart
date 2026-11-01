import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/state/library_item.dart';
import 'package:kartka/library/state/library_query.dart';

LibraryItem _item(
  String key, {
  String? title,
  int added = 0,
  int? lastRead,
  int? unread,
  bool downloaded = false,
  bool tracked = false,
  Set<String> categories = const {},
}) => LibraryItem(
  key: key,
  sourceId: 's',
  mangaUrl: '/$key',
  title: title ?? key,
  addedAt: DateTime.utc(2026).add(Duration(days: added)),
  lastReadAt: lastRead == null
      ? null
      : DateTime.utc(2026).add(Duration(days: lastRead)),
  unread: unread,
  downloaded: downloaded,
  tracked: tracked,
  categoryIds: categories,
);

List<String> _keys(List<LibraryItem> items) => [for (final i in items) i.key];

void main() {
  final items = [
    _item('a', title: 'Berserk', added: 3, lastRead: 1, unread: 4),
    _item('b', title: 'akira', added: 1, unread: 0, downloaded: true),
    _item('c', title: 'Cowboy', added: 2, lastRead: 5, tracked: true),
    _item('d', title: 'Dorohedoro', unread: 9),
  ];

  test('default sorts by title, case-insensitive', () {
    expect(_keys(applyQuery(items, const LibraryQuery())), [
      'b',
      'a',
      'c',
      'd',
    ]);
  });

  test('descending reverses the order', () {
    const q = LibraryQuery(ascending: false);
    expect(_keys(applyQuery(items, q)), ['d', 'c', 'a', 'b']);
  });

  test('last read puts most recent first, never-read last', () {
    const q = LibraryQuery(sort: LibrarySort.lastRead);
    expect(_keys(applyQuery(items, q)), ['c', 'a', 'b', 'd']);
  });

  test('date added puts newest first', () {
    const q = LibraryQuery(sort: LibrarySort.dateAdded);
    expect(_keys(applyQuery(items, q)), ['a', 'c', 'b', 'd']);
  });

  test('unread puts most unread first, unknown counts as zero', () {
    const q = LibraryQuery(sort: LibrarySort.unread);
    expect(_keys(applyQuery(items, q)), ['d', 'a', 'b', 'c']);
  });

  test('filters combine with AND', () {
    expect(_keys(applyQuery(items, const LibraryQuery(unreadOnly: true))), [
      'a',
      'd',
    ]);
    expect(_keys(applyQuery(items, const LibraryQuery(downloadedOnly: true))), [
      'b',
    ]);
    expect(_keys(applyQuery(items, const LibraryQuery(trackedOnly: true))), [
      'c',
    ]);
    const both = LibraryQuery(unreadOnly: true, trackedOnly: true);
    expect(applyQuery(items, both), isEmpty);
  });

  test('search matches title substrings ignoring case and whitespace', () {
    expect(_keys(applyQuery(items, const LibraryQuery(search: '  KIR '))), [
      'b',
    ]);
    expect(applyQuery(items, const LibraryQuery(search: '   ')), hasLength(4));
  });

  test('category tab keeps members; null tab keeps the uncategorised', () {
    final sorted = [
      _item('m', categories: {'x'}),
      _item('u'),
    ];
    expect(_keys(applyQuery(sorted, const LibraryQuery(categoryId: 'x'))), [
      'm',
    ]);
    expect(_keys(applyQuery(sorted, const LibraryQuery())), ['u']);
  });

  test('a search spans every tab', () {
    final sorted = [
      _item('m', title: 'Monster', categories: {'x'}),
      _item('u', title: 'Mushishi'),
    ];
    for (final tab in [null, 'x', 'y']) {
      final q = LibraryQuery(categoryId: tab, search: 'm');
      expect(_keys(applyQuery(sorted, q)), ['m', 'u']);
    }
  });

  test('copyWith replaces only given fields and can clear the category', () {
    const q = LibraryQuery(categoryId: 'x', search: 'a');
    final changed = q.copyWith(sort: LibrarySort.unread, clearCategory: true);
    expect(changed.sort, LibrarySort.unread);
    expect(changed.categoryId, isNull);
    expect(changed.search, 'a');
    expect(q.copyWith(), q);
    expect(q.copyWith().hashCode, q.hashCode);
    expect(
      q.copyWith(
        ascending: false,
        unreadOnly: true,
        downloadedOnly: true,
        trackedOnly: true,
        categoryId: 'y',
        search: 'z',
      ),
      const LibraryQuery(
        categoryId: 'y',
        search: 'z',
        ascending: false,
        unreadOnly: true,
        downloadedOnly: true,
        trackedOnly: true,
      ),
    );
  });

  test('items differing only in source availability are unequal', () {
    const k = 'k';
    final at = DateTime.utc(2026);
    final up = LibraryItem(
      key: k,
      sourceId: 's',
      mangaUrl: '/',
      title: 't',
      addedAt: at,
    );
    final down = LibraryItem(
      key: k,
      sourceId: 's',
      mangaUrl: '/',
      title: 't',
      addedAt: at,
      sourceAvailable: false,
    );
    expect(up, isNot(down));
    expect(up.hashCode, isNot(down.hashCode));
  });

  test('unreadCount treats null as zero', () {
    expect(_item('z').unreadCount, 0);
    expect(_item('z', unread: 3).unreadCount, 3);
  });
}
