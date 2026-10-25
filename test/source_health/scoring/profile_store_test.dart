import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';

class _Sync implements SettingsSync {
  final calls = <(String, String?, SettingsVault)>[];
  final remote = StreamController<String>.broadcast();

  @override
  Future<void> changed(String key, String? value, SettingsVault vault) async =>
      calls.add((key, value, vault));

  @override
  Stream<String> get remoteChanges => remote.stream;

  @override
  Stream<Map<String, String>> watchProblems() => const Stream.empty();
}

final ScoringProfile _custom = defaultScoringProfile.copyWith(
  keepScore: 0.5,
  cuts: {HealthReason.subset},
);

void main() {
  late _Sync sync;
  late MemoryKeyValueStore local;

  Future<ScoringProfileStore> open([String? stored]) async {
    sync = _Sync();
    local = MemoryKeyValueStore();
    if (stored != null) await local.set(kScoringSetting, stored);
    final store = ScoringProfileStore(
      SyncedKeyValueStore(local, SettingsVault.plain, () => sync),
    );
    await store.ready;
    return store;
  }

  test('starts as DEFAULT when nothing is stored', () async {
    final store = await open();
    expect(store.profile.value, defaultScoringProfile);
  });

  test('reads the stored profile', () async {
    final store = await open(jsonEncode(_custom.toJson()));
    expect(store.profile.value, _custom);
  });

  for (final bad in ['not json', '[1]', '{"keepScore": 4}']) {
    test('an invalid stored profile ($bad) reads as DEFAULT', () async {
      final store = await open(bad);
      expect(store.profile.value, defaultScoringProfile);
    });
  }

  test('save stores the JSON and reports it to sync', () async {
    final store = await open();
    await store.save(_custom);
    expect(store.profile.value, _custom);
    final json = jsonEncode(_custom.toJson());
    expect(await local.get(kScoringSetting), json);
    expect(sync.calls, [(kScoringSetting, json, SettingsVault.plain)]);
  });

  test('saving DEFAULT (or reset) removes the setting', () async {
    final store = await open(jsonEncode(_custom.toJson()));
    await store.reset();
    expect(store.profile.value, defaultScoringProfile);
    expect(await local.get(kScoringSetting), isNull);
    expect(sync.calls.single, (kScoringSetting, null, SettingsVault.plain));
  });

  test('a profile with every weight 0 is invalid and ignored', () async {
    final store = await open();
    await store.save(
      defaultScoringProfile.copyWith(
        weights: const ScoreWeights(
          coverage: 0,
          chapterCompleteness: 0,
          uptime: 0,
          imageQuality: 0,
          speed: 0,
        ),
      ),
    );
    expect(store.profile.value, defaultScoringProfile);
    expect(sync.calls, isEmpty);
  });

  test('preview changes the value without storing anything', () async {
    final store = await open();
    store.preview(_custom);
    expect(store.profile.value, _custom);
    store.preview(_custom);
    expect(await local.get(kScoringSetting), isNull);
    expect(sync.calls, isEmpty);
  });

  test('a peer replacing the setting reloads it; other keys do not', () async {
    final store = await open();
    await local.set(kScoringSetting, jsonEncode(_custom.toJson()));
    sync.remote.add('reader.settings');
    await Future<void>.delayed(Duration.zero);
    expect(store.profile.value, defaultScoringProfile);
    sync.remote.add(kScoringSetting);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(store.profile.value, _custom);
  });
}
