import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';

import '../fixtures.dart';

void main() {
  test('parses every field of /kartka/source_health_meta', () {
    final m = SourceHealthMeta.fromJson(fixtureJson('meta.json'))!;
    expect(m.runId, '2026-10-24T12-00-00Z');
    expect(m.generatedAt, DateTime.utc(2026, 10, 24, 12));
    expect(m.candidates, 590);
    expect(m.tested, 585);
    expect(m.verdicts, const VerdictCounts(keep: 120, cut: 400, pending: 65));
    expect(m.skipped, const [
      SkippedGroup(
        index: 'keiyoushi',
        reason: 'nsfw',
        count: 3,
        names: ['Hentai A', 'Hentai B', 'Hentai C'],
      ),
      SkippedGroup(
        index: 'mangayomi',
        reason: 'duplicate of a native source',
        count: 2,
        names: ['MangaDex', 'Comick'],
      ),
    ]);
  });

  test('null unless a map; wrong-typed fields read as missing', () {
    expect(SourceHealthMeta.fromJson(null), isNull);
    expect(SourceHealthMeta.fromJson(const ['x']), isNull);
    final m = SourceHealthMeta.fromJson(const {
      'runId': 4,
      'generatedAt': 'soon',
      'candidates': 'many',
      'tested': 2.0,
      'verdicts': 'all keep',
      'skipped': [
        'junk',
        {'index': 'x', 'count': 'two', 'names': 'a'},
      ],
    })!;
    expect(m.runId, isNull);
    expect(m.generatedAt, isNull);
    expect(m.candidates, isNull);
    expect(m.tested, 2);
    expect(m.verdicts, isNull);
    expect(m.skipped, const [SkippedGroup(index: 'x', reason: '')]);
  });

  test('verdict counts default missing entries to zero', () {
    expect(
      VerdictCounts.fromJson(const {'keep': 1}),
      const VerdictCounts(keep: 1),
    );
    expect(VerdictCounts.fromJson(7), isNull);
  });

  test('toJson round-trips; equal values share hashCode', () {
    final a = SourceHealthMeta.fromJson(fixtureJson('meta.json'))!;
    final back = SourceHealthMeta.fromJson(a.toJson())!;
    expect(back, a);
    expect(back.hashCode, a.hashCode);
    expect(const SourceHealthMeta().toJson(), {'skipped': <Object?>[]});
    expect(a, isNot(const SourceHealthMeta()));
    final g = a.skipped.first;
    expect(SkippedGroup.fromJson(g.toJson()), g);
    expect(g.hashCode, SkippedGroup.fromJson(g.toJson())!.hashCode);
    expect(SkippedGroup.fromJson(3), isNull);
    const v = VerdictCounts(keep: 1, cut: 2, pending: 3);
    expect(VerdictCounts.fromJson(v.toJson()), v);
    expect(
      v.hashCode,
      const VerdictCounts(keep: 1, cut: 2, pending: 3).hashCode,
    );
  });
}
