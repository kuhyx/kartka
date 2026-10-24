import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/settings/settings_catalog.dart';
import 'package:kartka/sync/settings/sync_passphrase.dart';
import 'package:kartka/sync/settings/synced_settings.dart';

import '../fakes.dart';
import 'settings_harness.dart';

/// Rejects keys the desktop wrapper's `/secrets/` route rejects, the way
/// `WrapperKeyValueStore` does: with an [ArgumentError], not an Exception.
class _WrapperLikeSecrets extends MemoryKeyValueStore {
  static final _ok = RegExp(r'^[A-Za-z0-9._:-]+$');

  String _checked(String key) => _ok.hasMatch(key)
      ? key
      : throw ArgumentError.value(key, 'key', 'use [A-Za-z0-9._:-]');

  @override
  Future<String?> get(String key) => super.get(_checked(key));

  @override
  Future<void> set(String key, String value) => super.set(_checked(key), value);
}

const _url = 'suwayomi.serverUrl';

void main() {
  test('setting the passphrase on desktop never reads plain settings from '
      'the wrapper secret store, so later changes still sync', () async {
    final db = InMemoryRtdb();
    final engine = await engineFor('desktop', db);
    final secrets = _WrapperLikeSecrets();
    await secrets.set('suwayomi.password', 'pw');
    final s = SyncedSettings(
      started: Future.value(engine),
      start: () async => engine,
      kv: MemoryKeyValueStore(),
      secrets: secrets,
      passphrase: SyncPassphrase(secrets, fallback: () async => null),
      cipher: testCipher,
    );
    expect(kSyncedSettings.keys, contains(kAutoDownloadSetting));
    await s.setPassphrase('pp');
    await s.changed(_url, 'https://s.example', SettingsVault.plain);
    await s.settled;
    final settings = db.tree['settings']! as Map;
    expect(settings.keys, contains(rtdbKey('suwayomi.password')));
    expect((settings[rtdbKey(_url)]! as Map)['value'], 'https://s.example');
  });

  test('a step failing with an Error does not wedge later changes', () async {
    final engine = await engineFor('dev-a', InMemoryRtdb());
    final s = SyncedSettings(
      started: Future.value(engine),
      start: () async => engine,
      kv: MemoryKeyValueStore(),
      secrets: MemoryKeyValueStore(),
      passphrase: SyncPassphrase(
        MemoryKeyValueStore(),
        fallback: () async => throw StateError('keystore broke'),
      ),
      cipher: testCipher,
    );
    await s.changed('suwayomi.password', 'a', SettingsVault.secret);
    await s.changed(_url, 'https://s.example', SettingsVault.plain);
    await s.settled;
    expect(
      engine.shadow.node(settingPath(_url))?['value'],
      'https://s.example',
    );
  });
}
