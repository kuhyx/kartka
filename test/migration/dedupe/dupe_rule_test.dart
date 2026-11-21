import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/dedupe/dupe_rule.dart';

import '../fakes.dart';

const _blurb =
    'A young knight sworn to the frozen kingdom befriends an emperor '
    'penguin who can talk. Together they cross the ice sheet.';

const _other =
    'Penguin chef Knight runs a tiny ramen stall in Osaka and dreams of '
    'winning the national noodle championship against his rival bakery.';

Dupe _dupe(
  String source, {
  String title = 'Knight and Penguin',
  List<String> authors = const ['Sato Kenji'],
  String? description,
  int count = 10,
  SourceHealthSummary? health,
  bool installed = true,
  DateTime? newest,
}) {
  final chapters = [
    for (final c in chaptersOf(source, [for (var n = 1; n <= count; n++) n]))
      ChapterInfo(
        url: c.url,
        name: c.name,
        number: c.number,
        uploadedAt: newest?.subtract(Duration(days: count - c.number!.toInt())),
      ),
  ];
  return Dupe(
    entry: LibraryEntry(
      key: mangaKeyOf(source, '/m'),
      sourceId: source,
      mangaUrl: '/m',
      title: title,
      addedAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    ),
    facts: (
      details: MangaDetails(
        sourceId: source,
        url: '/m',
        title: title,
        authors: authors,
        description: description,
      ),
      chapters: chapters,
      readUrls: const {},
    ),
    health: health,
    installed: installed,
  );
}

SourceHealthSummary _h(HealthVerdict v, [int? rank]) =>
    SourceHealthSummary(verdict: v, rank: rank);

void main() {
  test('a sequel or a longer title is not the same series', () {
    expect(
      isDuplicate(_dupe('a'), _dupe('b', title: 'Knight and Penguin 2')),
      isFalse,
    );
    expect(
      isDuplicate(_dupe('a'), _dupe('b', title: 'Knight and Penguin Season 2')),
      isFalse,
    );
    expect(
      isDuplicate(_dupe('a'), _dupe('b', title: 'knight & penguin!')),
      isTrue,
    );
  });

  test('one entry is never a pair with itself', () {
    expect(isDuplicate(_dupe('a'), _dupe('a')), isFalse);
  });

  test('chapter counts: within 10 % or 3 apart', () {
    bool pair(int x, int y) =>
        isDuplicate(_dupe('a', count: x), _dupe('b', count: y));
    expect(pair(100, 110), isTrue);
    expect(pair(100, 112), isFalse);
    expect(pair(2, 5), isTrue);
    expect(pair(2, 6), isFalse);
  });

  test('descriptions veto only when clearly different', () {
    expect(
      isDuplicate(
        _dupe('a', description: _blurb),
        _dupe('b', description: 'Read online! $_blurb'),
      ),
      isTrue,
    );
    expect(
      isDuplicate(
        _dupe('a', description: _blurb),
        _dupe('b', description: _other),
      ),
      isFalse,
    );
    expect(
      isDuplicate(
        _dupe('a', authors: const [], description: _blurb),
        _dupe('b', authors: const []),
      ),
      isTrue,
    );
  });

  test('ranks: keep, pending, cut, then no record or not installed', () {
    final order = [
      _dupe('nothing', count: 50),
      _dupe('uninstalled', health: _h(HealthVerdict.keep, 1), installed: false),
      _dupe('cut', health: _h(HealthVerdict.cut, 1)),
      _dupe('pending', health: _h(HealthVerdict.pending, 1)),
      _dupe('keep9', health: _h(HealthVerdict.keep, 9)),
      _dupe('keep2', health: _h(HealthVerdict.keep, 2)),
    ]..sort(compareSuperior);
    expect(
      [for (final x in order) x.entry.sourceId],
      ['keep2', 'keep9', 'pending', 'cut', 'nothing', 'uninstalled'],
    );
  });

  test('ties: more chapters, newer chapter, then key', () {
    final keep = _h(HealthVerdict.keep);
    final order = [
      _dupe('z', health: keep),
      _dupe('aold', health: keep, newest: DateTime.utc(2020)),
      _dupe('znew', health: keep, newest: DateTime.utc(2026)),
      _dupe('long', health: keep, count: 11),
      _dupe('a', health: keep),
    ]..sort(compareSuperior);
    expect(
      [for (final x in order) x.entry.sourceId],
      ['long', 'znew', 'aold', 'a', 'z'],
    );
  });

  test('a plan checks each loser against its winner directly', () {
    final a = _dupe('a', health: _h(HealthVerdict.keep, 1));
    final b = _dupe('b', authors: const [], health: _h(HealthVerdict.keep, 2));
    final c = _dupe(
      'c',
      authors: const ['Mori Aya'],
      health: _h(HealthVerdict.keep, 3),
    );
    final plan = planMerges([c, b, a]);
    expect(
      [
        for (final g in plan)
          [
            g.winner.entry.sourceId,
            for (final l in g.losers) l.entry.sourceId,
          ].join('<'),
      ],
      ['a<b'],
    );
  });
}
