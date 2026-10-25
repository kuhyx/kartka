import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/labels.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/scoring/profile.dart';

void main() {
  group('record defaultScore', () {
    test('round-trips, compares and hashes by value', () {
      final r = SourceHealthRecord.fromJson(const {
        'id': 'x',
        'score': 0.5,
        'defaultScore': 0.85,
      })!;
      expect(r.defaultScore, 0.85);
      expect(r.toJson()['defaultScore'], 0.85);
      expect(SourceHealthRecord.fromJson(r.toJson()), r);
      final other = SourceHealthRecord.fromJson(const {
        'id': 'x',
        'score': 0.5,
        'defaultScore': 0.8,
      })!;
      expect(other, isNot(r));
      expect(other.hashCode, isNot(r.hashCode));
    });

    test('absent or malformed reads as missing', () {
      expect(
        SourceHealthRecord.fromJson(const {'id': 'x'})!.defaultScore,
        isNull,
      );
      expect(
        SourceHealthRecord.fromJson(const {'id': 'x', 'defaultScore': 'hi'})!
            .defaultScore,
        isNull,
      );
    });

    test('the note shows only when it reads differently from the score', () {
      SourceHealthRecord rec(double score, double? d) =>
          SourceHealthRecord(id: 'x', name: 'x', score: score, defaultScore: d);
      expect(defaultScoreNote(rec(0.5, 0.85)), 'default 0.85');
      expect(defaultScoreNote(rec(0.851, 0.852)), isNull);
      expect(defaultScoreNote(rec(0.5, null)), isNull);
    });

    test('withJudgement replaces only the judgement', () {
      const r = SourceHealthRecord(id: 'x', name: 'X', flags: ['f']);
      final j = r.withJudgement(
        score: 0.4,
        defaultScore: 0.6,
        rank: 2,
        verdict: HealthVerdict.cut,
      );
      expect((j.score, j.defaultScore, j.rank), (0.4, 0.6, 2));
      expect(j.verdict, HealthVerdict.cut);
      expect((j.id, j.name), ('x', 'X'));
      expect(j.flags, ['f']);
    });
  });

  group('meta profile', () {
    final custom = defaultScoringProfile.copyWith(
      keepScore: 0.5,
      cuts: {HealthReason.subset},
    );

    test('parses, names and round-trips the run profile', () {
      final m = SourceHealthMeta.fromJson({
        'runId': 'r',
        'profile': {'name': 'custom', ...custom.toJson()},
      })!;
      expect(m.profile, custom);
      expect(m.toJson()['profile'], {'name': 'custom', ...custom.toJson()});
      expect(SourceHealthMeta.fromJson(m.toJson()), m);
      final plain = SourceHealthMeta.fromJson({
        'profile': defaultScoringProfile.toJson(),
      })!;
      expect(plain.toJson()['profile'], {
        'name': 'default',
        ...defaultScoringProfile.toJson(),
      });
      expect(plain, isNot(m));
      expect(plain.hashCode, isNot(m.hashCode));
    });

    test('absent or invalid reads as missing', () {
      expect(SourceHealthMeta.fromJson(const {'runId': 'r'})!.profile, isNull);
      expect(
        SourceHealthMeta.fromJson(const {
          'profile': {'keepScore': 9},
        })!.profile,
        isNull,
      );
    });

    test('withVerdicts replaces only the totals', () {
      const m = SourceHealthMeta(runId: 'r', tested: 3);
      final n = m.withVerdicts(const VerdictCounts(keep: 1, cut: 2));
      expect(n.verdicts, const VerdictCounts(keep: 1, cut: 2));
      expect((n.runId, n.tested), ('r', 3));
    });
  });

  group('profile value semantics', () {
    test('equal profiles share a hash; weights and cuts take part', () {
      final a = defaultScoringProfile.copyWith(cuts: {HealthReason.uptime});
      final b = defaultScoringProfile.copyWith(cuts: {HealthReason.uptime});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(defaultScoringProfile));
      expect(a.name, 'custom');
      expect(
        defaultScoringProfile.weights,
        isNot(const ScoreWeights(coverage: 0.5)),
      );
      expect(const ScoreWeights().hashCode, const ScoreWeights().hashCode);
    });

    test('toJson names every switch and weight', () {
      final json = defaultScoringProfile.toJson();
      expect((json['weights']! as Map).keys, ScoreWeights.keys);
      expect((json['cuts']! as Map).keys, kCutWireNames.values);
    });
  });
}
