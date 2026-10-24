import 'dart:convert';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show kAccountKey;
import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/settings/sync_passphrase.dart';
import 'package:kartka/sync/settings/synced_settings.dart';
import 'package:kartka/sync/sync_engine.dart';

import '../fakes.dart';
import 'settings_harness.dart';

SyncedSettings _service({
  required Future<SyncEngine> started,
  required Future<SyncEngine> Function() start,
  Future<String?> Function()? password,
}) => SyncedSettings(
  started: started,
  start: start,
  kv: MemoryKeyValueStore(),
  secrets: MemoryKeyValueStore(),
  passphrase: SyncPassphrase(
    MemoryKeyValueStore(),
    fallback: password ?? () async => 'p',
  ),
  cipher: testCipher,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the sync password is read from the keystore account', () async {
    installFakeSecureStorage(
      initial: {
        kAccountKey: jsonEncode({'email': 'a@b', 'password': 'pw'}),
      },
    );
    expect(await storedSyncPassword(), 'pw');
  });

  test('a Google or seeded account has no sync password', () async {
    installFakeSecureStorage(
      initial: {
        kAccountKey: jsonEncode({'email': 'a@b', 'password': ''}),
      },
    );
    expect(await storedSyncPassword(), isNull);
    installFakeSecureStorage();
    expect(await storedSyncPassword(), isNull);
  });

  test('a passphrase is kept even when the engine cannot start', () async {
    final s = _service(
      started: Future.error(StateError('no keystore')),
      start: () => Future.error(StateError('no keystore')),
    );
    await s.setPassphrase('pp');
    expect(await s.passphrase.key(), 'pp');
  });

  test('an engine that cannot start leaves settings local only', () async {
    final s = _service(
      started: Future.error(StateError('no keystore')),
      start: () => Future.error(StateError('no keystore')),
    );
    await s.changed('reader.settings', '{}', SettingsVault.plain);
    await s.settled;
    expect(await s.watchProblems().first, isEmpty);
  });

  test('a failing step is logged and later changes still run', () async {
    final engine = await engineFor('dev-a', InMemoryRtdb());
    var calls = 0;
    final s = _service(
      started: Future.value(engine),
      start: () async => engine,
      password: () async {
        calls++;
        throw const FormatException('keystore broke');
      },
    );
    await s.changed('suwayomi.password', 'a', SettingsVault.secret);
    await s.changed('suwayomi.password', 'b', SettingsVault.secret);
    await s.changed('reader.settings', '{}', SettingsVault.plain);
    await s.settled;
    expect(calls, 2);
    expect(engine.shadow.node('settings/reader~2Esettings')?['value'], '{}');
  });
}
