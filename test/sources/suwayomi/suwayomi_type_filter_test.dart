import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/sources/suwayomi/suwayomi_queries.dart';
import 'package:kartka/sources/suwayomi/suwayomi_type_filter.dart';

/// `test/fixtures/suwayomi/filters_<name>.json`, recorded from the live
/// server with [SuwayomiQueries.sourceFilters] (2026-11-21).
Map<String, Object?> _recorded(String name) => jsonDecode(
  File('test/fixtures/suwayomi/filters_$name.json').readAsStringSync(),
) as Map<String, Object?>;

SuwayomiTypeFilter _parsed(String name) => SuwayomiTypeFilter.fromResponse(
  _recorded(name)['response']! as Map<String, Object?>,
);

Map<String, Object?> _tick(int group, int child, {required bool on}) => {
  'position': group,
  'groupChange': {'position': child, 'checkBoxState': on},
};

const _manga = ContentTypes({ContentType.manga});
const _mangaManhwa = ContentTypes({ContentType.manga, ContentType.manhwa});

void main() {
  test('fixtures were recorded with the client document', () {
    for (final name in ['mangafire', 'mangadex']) {
      final request = _recorded(name)['request']! as Map<String, Object?>;
      expect(request['query'], SuwayomiQueries.sourceFilters);
    }
  });

  group('MangaFire (Type group, "Sort by" select)', () {
    final f = _parsed('mangafire');

    test('manga ticks manga and "Other" (unknown counts as manga)', () {
      expect(f.changesFor(Listing.search, _manga), [
        _tick(2, 0, on: true),
        _tick(2, 1, on: false),
        _tick(2, 2, on: false),
        _tick(2, 3, on: true),
      ]);
    });

    test('manga+manhwa ticks both', () {
      final changes = f.changesFor(Listing.search, _mangaManhwa)!;
      expect(changes.take(2), [_tick(2, 0, on: true), _tick(2, 1, on: true)]);
      expect(changes.skip(2), [_tick(2, 2, on: false), _tick(2, 3, on: true)]);
    });

    test('manhwa+manhua leaves manga and "Other" out', () {
      final types = ContentTypes.all.toggled(ContentType.manga);
      expect(f.changesFor(Listing.search, types), [
        _tick(2, 0, on: false),
        _tick(2, 1, on: true),
        _tick(2, 2, on: true),
        _tick(2, 3, on: false),
      ]);
    });

    test('popular sorts by most viewed, latest by latest update', () {
      expect(f.changesFor(Listing.popular, _manga)!.last, {
        'position': 16,
        'selectState': 8,
      });
      expect(f.changesFor(Listing.latest, _manga)!.last, {
        'position': 16,
        'selectState': 0,
      });
    });

    test('all sends no filters', () {
      for (final l in Listing.values) {
        expect(f.changesFor(l, ContentTypes.all), isNull);
        expect(f.changesFor(l, ContentTypes.none), isNull);
      }
    });
  });

  test('MangaDex: "Original language" group, Sort filter descending', () {
    final f = _parsed('mangadex');
    final popular = f.changesFor(Listing.popular, _mangaManhwa)!;
    expect(popular, [
      _tick(1, 0, on: true),
      _tick(1, 1, on: false),
      _tick(1, 2, on: true),
      {
        'position': 5,
        'sortState': {'index': 2, 'ascending': false},
      },
    ]);
    expect(f.changesFor(Listing.latest, _manga)!.last, {
      'position': 5,
      'sortState': {'index': 1, 'ascending': false},
    });
  });

  test('a source without a type filter cannot narrow anything', () {
    final f = SuwayomiTypeFilter.parse(const [
      {'__typename': 'HeaderFilter'},
      {
        '__typename': 'GroupFilter',
        'name': 'Genres',
        'filters': [
          {'__typename': 'CheckBoxFilter', 'name': 'Action'},
        ],
      },
      {
        '__typename': 'SelectFilter',
        'name': 'Order',
        'values': ['Popular', 'Latest'],
      },
    ]);
    for (final l in Listing.values) {
      expect(f.changesFor(l, _manga), isNull);
    }
  });

  test('tri-state type children are included or ignored', () {
    final f = SuwayomiTypeFilter.parse(const [
      {
        '__typename': 'GroupFilter',
        'name': 'Comic type',
        'filters': [
          {'__typename': 'TriStateFilter', 'name': 'Manhwa'},
          {'__typename': 'TriStateFilter', 'name': 'Manga'},
          {'__typename': 'HeaderFilter'},
        ],
      },
    ]);
    expect(f.changesFor(Listing.search, _manga), [
      {
        'position': 0,
        'groupChange': {'position': 0, 'triState': 'IGNORE'},
      },
      {
        'position': 0,
        'groupChange': {'position': 1, 'triState': 'INCLUDE'},
      },
    ]);
    // No sort filter: Popular and Latest stay unfiltered.
    expect(f.changesFor(Listing.popular, _manga), isNull);
  });

  test('a type select picks one type, but cannot express two', () {
    final f = SuwayomiTypeFilter.parse(const [
      {
        '__typename': 'SelectFilter',
        'name': 'Type',
        'values': ['All', 'Manhua', 'Manga', 'Manhwa'],
      },
      {
        '__typename': 'SortFilter',
        'name': 'Sort',
        'values': ['Name', 'Trending'],
      },
    ]);
    expect(f.changesFor(Listing.search, _manga), [
      {'position': 0, 'selectState': 2},
    ]);
    expect(
      f.changesFor(Listing.search, const ContentTypes({ContentType.manhwa})),
      [
        {'position': 0, 'selectState': 3},
      ],
    );
    expect(f.changesFor(Listing.search, _mangaManhwa), isNull);
    // A sort without a latest option leaves Latest unfiltered.
    expect(f.changesFor(Listing.latest, _manga), isNull);
    expect(f.changesFor(Listing.popular, _manga)!.last, {
      'position': 1,
      'sortState': {'index': 1, 'ascending': false},
    });
  });

  test('a "type" filter without a manga option is not a type filter', () {
    final f = SuwayomiTypeFilter.parse(const [
      {
        '__typename': 'SelectFilter',
        'name': 'Type',
        'values': ['Ongoing', 'Completed'],
      },
    ]);
    expect(f.changesFor(Listing.search, _manga), isNull);
  });
}
