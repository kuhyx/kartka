import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/settings/settings_cipher.dart';
import 'package:kartka/sync/settings/synced_settings.dart';
import 'package:kartka/sync/sync_engine.dart';

import '../fakes.dart';

/// One cipher for every simulated device: cheap iterations, shared key cache.
final testCipher = SettingsCipher(iterations: 1000);

/// One simulated install's settings: the platform stores, the synced views
/// features get, and the sync service between them and a shared RTDB.
class SettingsDevice {
  new _(
    this.engine,
    this.local,
    this.secretsLocal,
    this.settings,
    this.shadowKv,
  ) : kv = SyncedKeyValueStore(local, SettingsVault.plain, () => settings),
      secrets = SyncedKeyValueStore(
        secretsLocal,
        SettingsVault.secret,
        () => settings,
      );

  /// Builds device [id] over [db]; [password] is its stored sync password.
  static Future<SettingsDevice> create(
    String id,
    InMemoryRtdb db, {
    TestClock? clock,
    String? password = 'sync-pass',
    MemoryKeyValueStore? shadowKv,
  }) async {
    final shadow = shadowKv ?? MemoryKeyValueStore();
    final engine = await engineFor(id, db, clock: clock, kv: shadow);
    final local = MemoryKeyValueStore();
    final secrets = MemoryKeyValueStore();
    final device = SettingsDevice._(
      engine,
      local,
      secrets,
      SyncedSettings(
        started: Future.value(engine),
        start: () async => engine,
        kv: local,
        secrets: secrets,
        syncPassword: () async => password,
        cipher: testCipher,
      ),
      shadow,
    );
    await device.settle();
    return device;
  }

  /// The engine.
  final SyncEngine engine;

  /// The platform's plain store, as the sync service writes it.
  final MemoryKeyValueStore local;

  /// The platform's secret store.
  final MemoryKeyValueStore secretsLocal;

  /// The service under test.
  final SyncedSettings settings;

  /// What features write plain settings through.
  final SyncedKeyValueStore kv;

  /// What features write secrets through.
  final SyncedKeyValueStore secrets;

  /// Where the engine persists its shadow.
  final MemoryKeyValueStore shadowKv;

  /// Waits until every queued publish and replay finished.
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await pumpEventQueue();
      await settings.settled;
    }
  }

  /// Pushes nothing new, pulls the peers' changes and replays them.
  Future<void> poll() async {
    await settle();
    await engine.poll();
    await settle();
  }
}
