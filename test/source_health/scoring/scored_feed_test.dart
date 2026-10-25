import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/scoring/scored_feed.dart';

class _Feed implements SourceHealthFeed {
  int watches = 0;
  int metaWatches = 0;
  final records = StreamController<List<SourceHealthRecord>>.broadcast();
  final meta = StreamController<SourceHealthMeta?>.broadcast();

  @override
  Stream<List<SourceHealthRecord>> watch() {
    watches++;
    return records.stream;
  }

  @override
  Stream<SourceHealthMeta?> watchMeta() {
    metaWatches++;
    return meta.stream;
  }
}

SourceHealthRecord rec(String id, {double coverage = 1, String? verdict}) =>
    SourceHealthRecord.fromJson({
      'id': id,
      'coverage': {'ratio': coverage},
      'chapterCompleteness': {'medianRatio': 1},
      'uptime': {'ratio': 1, 'status': 'final'},
      'imageQuality': {'medianWidthPx': 1400},
      'latencyMs': {'p95': 0},
      'blocking': {'challengeRate': 0},
      'score': 0.123,
      'rank': 7,
      'verdict': verdict ?? 'cut',
    })!;

const _onlyCoverage = ScoringProfile(
  weights: ScoreWeights(
    coverage: 1,
    chapterCompleteness: 0,
    uptime: 0,
    imageQuality: 0,
    speed: 0,
  ),
  keepScore: 0.8,
);

void main() {
  late _Feed base;
  late ScoringProfileStore store;
  late ScoredHealthFeed feed;

  setUp(() async {
    base = _Feed();
    store = ScoringProfileStore(
      SyncedKeyValueStore(
        MemoryKeyValueStore(),
        SettingsVault.plain,
        () => null,
      ),
    );
    feed = ScoredHealthFeed(base, store);
    await store.ready;
  });

  test('under DEFAULT the published judgement is shown untouched', () async {
    final out = <List<SourceHealthRecord>>[];
    final sub = feed.watch().listen(out.add);
    base.records.add([rec('a')]);
    await pumpEventQueue();
    expect(out.single.single.score, 0.123);
    expect(out.single.single.rank, 7);
    await sub.cancel();
  });

  test('a custom profile re-scores, re-ranks and re-judges live', () async {
    final out = <List<SourceHealthRecord>>[];
    final metas = <SourceHealthMeta?>[];
    final subs = [
      feed.watch().listen(out.add),
      feed.watchMeta().listen(metas.add),
    ];
    base.meta.add(const SourceHealthMeta(runId: 'r', tested: 2));
    base.records.add([rec('a', coverage: 0.5), rec('b')]);
    await pumpEventQueue();
    expect(out.last.map((r) => r.verdict.name), ['cut', 'cut']);
    expect(out.last.map((r) => r.score), [0.123, 0.123]);

    store.preview(_onlyCoverage);
    await pumpEventQueue();
    expect(out.last.map((r) => (r.id, r.score, r.rank, r.verdict)), [
      ('b', 1.0, 1, HealthVerdict.keep),
      ('a', 0.5, 2, HealthVerdict.cut),
    ]);
    expect(metas.last!.verdicts, const VerdictCounts(keep: 1, cut: 1));
    expect(metas.last!.runId, 'r');

    store.preview(defaultScoringProfile);
    await pumpEventQueue();
    expect(out.last.first.score, 0.123);
    for (final s in subs) {
      await s.cancel();
    }
  });

  test('records and meta share one subscription to the base feed', () async {
    final a = feed.watch().listen((_) {});
    final b = feed.watchMeta().listen((_) {});
    expect((base.watches, base.metaWatches), (1, 1));
    await a.cancel();
    expect(base.records.hasListener, isTrue);
    await b.cancel();
    expect(base.records.hasListener, isFalse);
    expect(base.meta.hasListener, isFalse);
    final again = feed.watch().listen((_) {});
    expect(base.watches, 2);
    await again.cancel();
  });

  test(
    'records the evaluator judged with the active profile pass through',
    () async {
      final out = <List<SourceHealthRecord>>[];
      final sub = feed.watch().listen(out.add);
      store.preview(_onlyCoverage);
      base.meta.add(
        const SourceHealthMeta(
          verdicts: VerdictCounts(keep: 9),
          profile: _onlyCoverage,
        ),
      );
      base.records.add([rec('a', coverage: 0.5)]);
      await pumpEventQueue();
      expect(out.last.single.score, 0.123);
      await sub.cancel();
    },
  );

  test('read errors reach the listener; meta errors are dropped', () async {
    final errors = <Object>[];
    final sub = feed.watch().listen((_) {}, onError: errors.add);
    base.records.addError(StateError('offline'));
    base.meta.addError(StateError('meta offline'));
    await pumpEventQueue();
    expect(errors.single, isA<StateError>());
    await sub.cancel();
  });

  test('emits nothing until the stored profile has been read', () async {
    final slow = Completer<void>();
    final local = _SlowKv(slow.future);
    final s = ScoringProfileStore(
      SyncedKeyValueStore(local, SettingsVault.plain, () => null),
    );
    final f = ScoredHealthFeed(base, s);
    final out = <List<SourceHealthRecord>>[];
    final sub = f.watch().listen(out.add);
    base.records.add([rec('a')]);
    await pumpEventQueue();
    expect(out, isEmpty);
    slow.complete();
    await pumpEventQueue();
    expect(out, hasLength(1));
    await sub.cancel();
  });

  test('cancelling before the profile is read stops quietly', () async {
    final slow = Completer<void>();
    final s = ScoringProfileStore(
      SyncedKeyValueStore(
        _SlowKv(slow.future),
        SettingsVault.plain,
        () => null,
      ),
    );
    final f = ScoredHealthFeed(base, s);
    final out = <List<SourceHealthRecord>>[];
    final sub = f.watch().listen(out.add);
    base.records.add([rec('a')]);
    await sub.cancel();
    slow.complete();
    await pumpEventQueue();
    expect(out, isEmpty);
  });
}

/// A store whose first read waits for [_gate].
class _SlowKv extends MemoryKeyValueStore {
  new(this._gate);

  final Future<void> _gate;

  @override
  Future<String?> get(String key) => _gate.then((_) => super.get(key));
}
