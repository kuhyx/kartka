import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/scoring/scored_feed.dart';

import 'scored_feed_test.dart' show rec;

/// A base feed that, like the RTDB poller, emits only when the data changes.
class _Feed implements SourceHealthFeed {
  final records = StreamController<List<SourceHealthRecord>>.broadcast();
  final meta = StreamController<SourceHealthMeta?>.broadcast();

  @override
  Stream<List<SourceHealthRecord>> watch() => records.stream;

  @override
  Stream<SourceHealthMeta?> watchMeta() => meta.stream;
}

void main() {
  late _Feed base;
  late ScoredHealthFeed feed;

  setUp(() async {
    base = _Feed();
    final store = ScoringProfileStore(
      SyncedKeyValueStore(
        MemoryKeyValueStore(),
        SettingsVault.plain,
        () => null,
      ),
    );
    feed = ScoredHealthFeed(base, store);
    await store.ready;
  });

  test('a late listener gets the latest snapshot, then live ones', () async {
    final first = feed.watch().listen((_) {});
    base.meta.add(const SourceHealthMeta(runId: 'r', tested: 1));
    base.records.add([rec('a')]);
    await pumpEventQueue();

    final records = <List<SourceHealthRecord>>[];
    final metas = <SourceHealthMeta?>[];
    final joined = feed.watch().listen(records.add);
    final joinedMeta = feed.watchMeta().listen(metas.add);
    await pumpEventQueue();
    expect(records.single.single.id, 'a');
    expect(metas.single?.runId, 'r');

    base.records.add([rec('b')]);
    await pumpEventQueue();
    expect(records.map((r) => r.single.id), ['a', 'b']);
    await first.cancel();
    await joined.cancel();
    await joinedMeta.cancel();
  });

  test(
    'a late listener gets the latest error, until data replaces it',
    () async {
      final first = feed.watch().listen((_) {}, onError: (Object _) {});
      base.records.add([rec('a')]);
      base.records.addError(StateError('offline'));
      await pumpEventQueue();

      final errors = <Object>[];
      final records = <List<SourceHealthRecord>>[];
      final joined = feed.watch().listen(records.add, onError: errors.add);
      await pumpEventQueue();
      expect(records, isEmpty);
      expect(errors, [isA<StateError>()]);

      base.records.add([rec('b')]);
      await pumpEventQueue();
      final later = <List<SourceHealthRecord>>[];
      final last = feed.watch().listen(later.add, onError: errors.add);
      await pumpEventQueue();
      expect(later.single.single.id, 'b');
      expect(errors, hasLength(1));
      await first.cancel();
      await joined.cancel();
      await last.cancel();
    },
  );
}
