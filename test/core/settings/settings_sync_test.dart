import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

class _Recorder implements SettingsSync {
  final calls = <(String, String?, SettingsVault)>[];
  final remote = StreamController<String>.broadcast();

  @override
  Future<void> changed(String key, String? value, SettingsVault vault) async =>
      calls.add((key, value, vault));

  @override
  Stream<String> get remoteChanges => remote.stream;

  @override
  Stream<Map<String, String>> watchProblems() => Stream.value({'k': 'bad'});
}

void main() {
  test('writes land locally and are reported to sync', () async {
    final local = MemoryKeyValueStore();
    final sync = _Recorder();
    final kv = SyncedKeyValueStore(local, SettingsVault.secret, () => sync);
    await kv.set('a', '1');
    await kv.remove('a');
    await kv.set('b', '2');
    expect(await kv.get('b'), '2');
    expect(await kv.entries(), {'b': '2'});
    expect(await local.get('b'), '2');
    expect(sync.calls, [
      ('a', '1', SettingsVault.secret),
      ('a', null, SettingsVault.secret),
      ('b', '2', SettingsVault.secret),
    ]);
  });

  test('without a sync service it is just the local store', () async {
    final kv = SyncedKeyValueStore(
      MemoryKeyValueStore(),
      SettingsVault.plain,
      () => null,
    );
    await kv.set('a', '1');
    expect(await kv.get('a'), '1');
    expect(await kv.remoteChanges.isEmpty, isTrue);
    expect(await kv.watchProblems().isEmpty, isTrue);
  });

  test('the lookup runs only after the subscriber yields', () async {
    final sync = _Recorder();
    SettingsSync? registry;
    final kv = SyncedKeyValueStore(
      MemoryKeyValueStore(),
      SettingsVault.plain,
      () => registry!,
    );
    final seen = <String>[];
    kv.remoteChanges.listen(seen.add);
    // Like KartkaRegistry.build: the service exists only after every
    // factory (which may subscribe) has returned.
    registry = sync;
    await pumpEventQueue();
    sync.remote.add('reader.settings');
    await pumpEventQueue();
    expect(seen, ['reader.settings']);
    expect(await kv.watchProblems().first, {'k': 'bad'});
  });
}
