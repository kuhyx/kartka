import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/candidates/candidate_finder.dart';

import '../fakes.dart';

const _knight =
    'A young knight sworn to the frozen kingdom befriends an emperor '
    'penguin who can talk. Together they cross the ice sheet to stop the '
    'sorcerer who stole the midnight sun from the capital.';

const _cook =
    'Penguin chef Knight runs a tiny ramen stall in Osaka and dreams of '
    'winning the national noodle championship against his rival bakery.';

const _title = 'Knight and Penguin';

LibraryEntry _entry({String sourceId = 'old'}) => LibraryEntry(
  key: mangaKeyOf(sourceId, '/kp'),
  sourceId: sourceId,
  mangaUrl: '/kp',
  title: _title,
  addedAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
);

/// The entry's own source, knowing the real series.
ScriptedSource _own({String? alt}) {
  final own = ScriptedSource('old', name: 'Old');
  own.detailMap['/kp'] = MangaDetails(
    sourceId: 'old',
    url: '/kp',
    title: _title,
    authors: const ['Sato Kenji'],
    description: alt == null ? _knight : '$_knight\nAlternative Titles: $alt',
  );
  own.chapterLists['/kp'] = chaptersOf('/kp', [
    for (var i = 1; i <= 40; i++) i,
  ]);
  return own;
}

void main() {
  _firstOfTests();
  test('the same title by another author ranks below the real series, '
      'even from a better source and listed first', () async {
    final best = ScriptedSource('best', name: 'Best')
      ..offerFull(
        _title,
        _title,
        '/wrong',
        authors: ['Mori Aya'],
        description: _cook,
        chapterCount: 41,
      );
    final good = ScriptedSource('good', name: 'Good')
      ..offerFull(
        _title,
        'Knight & Penguin',
        '/right',
        authors: ['Kenji Sato'],
        description: _knight,
        chapterCount: 39,
        newest: DateTime.utc(2026, 11, 20),
      );
    final found = await CandidateFinder([best, good])
        .find(_entry(), own: _own());
    expect([for (final c in found.best) c.manga.url], ['/right', '/wrong']);
    final top = found.best.first;
    expect(top.source, same(good));
    expect(top.chapters, 39);
    expect(top.newest, DateTime.utc(2026, 11, 20));
    expect(top.description, _knight);
    expect(top.previewChapterUrl, '/right/1');
    expect(found.ownChapters, 40);
    expect(found.lanes.map((l) => l.state), [LaneState.found, LaneState.found]);
  });

  test('a failing or slow source is a failed lane; the others still give '
      'candidates', () async {
    final broken = ScriptedSource('broken')
      ..searchError = StateError('HTTP error 400');
    final slow = ScriptedSource('slow')..gate = Completer<void>();
    final fine = ScriptedSource('fine')..offer(_title, _title, '/f');
    final empty = ScriptedSource('empty');
    final found = await CandidateFinder([
      broken,
      slow,
      fine,
      empty,
    ], timeout: const Duration(milliseconds: 50)).find(_entry());
    expect(
      {for (final l in found.lanes) l.source.ref.id: l.state},
      {
        'broken': LaneState.failed,
        'slow': LaneState.failed,
        'fine': LaneState.found,
        'empty': LaneState.empty,
      },
    );
    expect(found.best.single.manga.url, '/f');
  });

  test('with no good hit for the title, each alt title is searched', () async {
    final alt = ScriptedSource('alt')
      ..offer(_title, 'Penguin Highway', '/ph')
      ..offer('Kishi to Pengin', 'Kishi to Pengin', '/kp');
    final direct = ScriptedSource('direct')..offer(_title, _title, '/d');
    final found = await CandidateFinder([alt, direct])
        .find(_entry(), own: _own(alt: 'Kishi to Pengin'));
    expect(alt.searched, [_title, 'Kishi to Pengin']);
    expect(direct.searched, [_title]);
    expect({for (final c in found.best) c.manga.url}, {'/kp', '/d'});
  });

  test('searches are cached per source and query for the session', () async {
    final s = ScriptedSource('s')..offer(_title, _title, '/s');
    final finder = CandidateFinder([s]);
    await finder.find(_entry());
    await finder.find(_entry());
    expect(s.searched, [_title]);
  });

  test(
    "the entry's own source is skipped and at most 5 are searched",
    () async {
      final all = [for (var i = 0; i < 7; i++) ScriptedSource('s$i')];
      await CandidateFinder(all).find(_entry(sourceId: 's1'));
      expect([for (final s in all) s.searched.length], [1, 0, 1, 1, 1, 1, 0]);
    },
  );

  test('keeps 5 best; ties go to the better source, then more chapters, '
      'then the newer chapter', () async {
    final a = ScriptedSource('a');
    final b = ScriptedSource('b');
    for (final (url, count, day) in [
      ('/a1', 5, 1),
      ('/a2', 9, 1),
      ('/a3', 9, 3),
      ('/a4', 2, 1),
      ('/a5', 1, 1),
    ]) {
      a
        ..offer(_title, _title, url)
        ..chapterLists[url] = [
          for (var n = count; n >= 1; n--)
            ChapterInfo(
              url: '$url/$n',
              name: '$n',
              number: n.toDouble(),
              uploadedAt: DateTime.utc(2026, 1, day),
            ),
        ];
    }
    b.offer(_title, _title, '/b1');
    final found = await CandidateFinder([a, b]).find(_entry());
    expect(
      [for (final c in found.best) c.manga.url],
      ['/a3', '/a2', '/a1', '/a4', '/a5'],
    );
    expect(a.detailed, hasLength(3)); // details only for the top 3
  });

  test('a manual query searches only it and matches against it', () async {
    final s = ScriptedSource('s')..offer('Pingu', 'Pingu Knight', '/p');
    final found = await CandidateFinder([s])
        .find(_entry(), query: 'Pingu Knight');
    expect(s.searched, ['Pingu Knight']);
    expect(found.best, isEmpty);
    s.offer('Pingu Knight', 'Pingu Knight', '/p');
    final again = await CandidateFinder([s])
        .find(_entry(), query: 'Pingu Knight');
    expect(again.best.single.manga.url, '/p');
  });

  test('migrationTargets: keep sources by rank, Atsumaru within the first '
      '5 when installed', () {
    final keep = [for (var i = 0; i < 6; i++) ScriptedSource('k$i')];
    final atsu = ScriptedSource(
      'suwayomi:2327480808438768017',
      name: 'Atsumaru',
    );
    final ranked = migrationTargets(keep, atsumaru: atsu);
    expect(ranked.indexOf(atsu), 4);
    expect(ranked, hasLength(7));
    expect(migrationTargets([keep.first, atsu], atsumaru: atsu), [
      keep.first,
      atsu,
    ]);
    expect(
      migrationTargets(keep.take(2).toList(), atsumaru: null),
      keep.take(2),
    );
  });
}

void _firstOfTests() {
  ChapterInfo ch(String url, [double? n]) =>
      ChapterInfo(url: url, name: url, number: n);
  test('firstOf: lowest number, else the last listed, else none', () {
    expect(firstOf([ch('/3', 3), ch('/x'), ch('/1', 1)])?.url, '/1');
    expect(firstOf([ch('/b'), ch('/a')])?.url, '/a');
    expect(firstOf(const []), isNull);
    expect(firstOf(null), isNull);
  });
}
