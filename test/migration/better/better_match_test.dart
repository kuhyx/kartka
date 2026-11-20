import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/better/better_match.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

import '../fakes.dart';

SourceHealthRecord _r(
  String id, {
  HealthVerdict verdict = HealthVerdict.keep,
  int? rank,
  List<String> cutReasons = const [],
  List<String> flags = const [],
  bool unreachable = false,
}) => SourceHealthRecord(
  id: id,
  name: id,
  verdict: verdict,
  rank: rank,
  cutReasons: cutReasons,
  flags: flags,
  unreachable: unreachable,
);

MangaSummary _m(String title) =>
    MangaSummary(sourceId: 's', url: '/$title', title: title);

void main() {
  group('moveReason', () {
    MoveReason? reason(
      SourceHealthRecord? r, {
      bool installed = true,
      String? flag,
      bool rejected = false,
    }) => moveReason(
      record: r,
      installed: installed,
      flag: flag,
      rejected: rejected,
    );

    test('a healthy keep source, or one without a record, stays', () {
      expect(reason(_r('a')), isNull);
      expect(reason(null), isNull);
      expect(reason(_r('a', verdict: HealthVerdict.pending)), isNull);
    });

    test('names why the source should be left', () {
      expect(reason(_r('a'), installed: false), MoveReason.notInstalled);
      expect(reason(null, installed: false), MoveReason.notInstalled);
      expect(reason(_r('a'), flag: 'x'), MoveReason.failedTest);
      expect(reason(_r('a', unreachable: true)), MoveReason.unreachable);
      expect(reason(_r('a', verdict: HealthVerdict.cut)), MoveReason.cut);
      expect(reason(_r('a', cutReasons: ['blocking'])), MoveReason.challenge);
      expect(reason(_r('a', flags: [reprobeOnlyFlag])), MoveReason.unreachable);
      expect(MoveReason.cut.label, 'its source is cut');
    });

    test('a source rejected for good moves, installed or not', () {
      expect(reason(null, rejected: true), MoveReason.cut);
      expect(reason(null, installed: false, rejected: true), MoveReason.cut);
      expect(reason(_r('a'), rejected: true), MoveReason.cut);
    });
  });

  test('targets: installed, unflagged, not rejected sources with a record, '
      'keep first, then by rank', () {
    final sources = {
      for (final id in ['k1', 'k2', 'k3', 'cut', 'flagged', 'gone', 'cut9'])
        id: ScriptedSource(id),
    };
    final targets = rankedTargets(
      [
        _r('k3'), // unranked keep: after the ranked keeps
        _r('k2', rank: 5),
        _r('missing', rank: 1), // not installed
        _r('cut9', verdict: HealthVerdict.cut, rank: 9),
        _r('cut', verdict: HealthVerdict.cut, rank: 1),
        _r('flagged', rank: 1),
        _r('gone', rank: 2), // rejected for good
        _r('k1', rank: 3),
      ],
      sources,
      flagOf: (id) => id == 'flagged' ? 'test failed' : null,
      rejected: const {'gone'},
    );
    expect(
      [for (final t in targets) t.record.id],
      ['k1', 'k2', 'k3', 'cut', 'cut9'],
    );
    expect(targets.first.source, same(sources['k1']));
  });

  group('titleMatch', () {
    test('an exact title wins over an earlier close one', () {
      final m = titleMatch('Chainsaw Man', [
        _m('Chainsaw-Man'),
        _m('chainsaw  man'),
      ]);
      expect(m?.title, 'chainsaw  man');
    });

    test('a close title in both directions matches', () {
      expect(
        titleMatch('Chainsaw Man', [_m('Chainsaw-Man')])?.title,
        'Chainsaw-Man',
      );
      expect(
        titleMatch('Solo Leveling', [_m('Solo Levelling')])?.title,
        'Solo Levelling',
      );
    });

    test('a title only contained in a longer one does not match', () {
      expect(titleMatch('Berserk', [_m('Berserk of Gluttony')]), isNull);
      expect(titleMatch('Naruto', [_m('Boruto')]), isNull);
      expect(titleMatch('One Piece', [_m('One Punch-Man')]), isNull);
      expect(titleMatch('One Piece', const []), isNull);
    });
  });
}
