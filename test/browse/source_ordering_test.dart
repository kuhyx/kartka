import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/source_ordering.dart';
import 'package:kartka/core/models/source_ref.dart';

SourceRef src(String id, String name, SourceOrigin origin) =>
    SourceRef(id: id, name: name, lang: 'en', origin: origin);

void main() {
  final md = src('mangadex', 'MangaDex', SourceOrigin.native);
  final s1 = src('suwayomi:1', 'Bato', SourceOrigin.suwayomi);
  final s2 = src('suwayomi:2', 'asura', SourceOrigin.suwayomi);
  final s3 = src('suwayomi:3', 'Comick', SourceOrigin.suwayomi);
  final local = src('local', 'Local', SourceOrigin.local);

  test('groups by origin in enum order and omits empty groups', () {
    final groups = groupSources([local, s1, md], const {});
    expect(groups.map((g) => g.origin), [
      SourceOrigin.native,
      SourceOrigin.suwayomi,
      SourceOrigin.local,
    ]);
  });

  test('without health data sorts by name case-insensitively', () {
    final groups = groupSources([s3, s1, s2], const {});
    expect(groups.single.sources, [s2, s1, s3]);
  });

  test('ranked sources come first by rank, unranked after by name', () {
    final groups = groupSources(
      [s1, s2, s3],
      const {
        'suwayomi:3': SourceHealthSummary(rank: 1, verdict: HealthVerdict.keep),
        'suwayomi:1': SourceHealthSummary(rank: 4, verdict: HealthVerdict.cut),
        'suwayomi:2': SourceHealthSummary(verdict: HealthVerdict.pending),
      },
    );
    expect(groups.single.sources, [s3, s1, s2]);
  });

  test('equal names fall back to id for a deterministic order', () {
    final a = src('plugin:b', 'Same', SourceOrigin.plugin);
    final b = src('plugin:a', 'Same', SourceOrigin.plugin);
    expect(groupSources([a, b], const {}).single.sources, [b, a]);
  });

  test('equal ranks fall back to name', () {
    final groups = groupSources(
      [s3, s1],
      const {
        'suwayomi:3': SourceHealthSummary(rank: 2, verdict: HealthVerdict.keep),
        'suwayomi:1': SourceHealthSummary(rank: 2, verdict: HealthVerdict.keep),
      },
    );
    expect(groups.single.sources, [s1, s3]);
  });

  test('HealthVerdict.parse maps wire values and defaults to pending', () {
    expect(HealthVerdict.parse('keep'), HealthVerdict.keep);
    expect(HealthVerdict.parse('cut'), HealthVerdict.cut);
    expect(HealthVerdict.parse('pending'), HealthVerdict.pending);
    expect(HealthVerdict.parse(null), HealthVerdict.pending);
    expect(HealthVerdict.parse('???'), HealthVerdict.pending);
  });

  test('SourceHealthSummary has value equality', () {
    const a = SourceHealthSummary(rank: 1, verdict: HealthVerdict.keep);
    const b = SourceHealthSummary(rank: 1, verdict: HealthVerdict.keep);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == const SourceHealthSummary(verdict: HealthVerdict.keep), false);
    expect(a.toString(), contains('rank: 1'));
  });
}
