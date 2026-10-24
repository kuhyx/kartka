import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_shadow.dart';

/// KeyValueStore over a plain map.
class MemoryKv implements KeyValueStore {
  /// Stored entries.
  final Map<String, String> data = {};

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> set(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in data.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}

/// A wall clock tests advance by hand.
class TestClock {
  /// Current time.
  DateTime now = DateTime.utc(2026, 10, 24, 12);

  /// Moves the clock forward.
  void advance([Duration by = const Duration(seconds: 1)]) => now = now.add(by);
}

/// An engine for [deviceId] over [db]; [signedIn] false means signed out.
Future<SyncEngine> engineFor(
  String deviceId,
  InMemoryRtdb db, {
  TestClock? clock,
  MemoryKv? kv,
  bool signedIn = true,
}) async {
  final c = clock ?? TestClock();
  return SyncEngine(
    shadow: await SyncShadow.load(kv ?? MemoryKv()),
    deviceId: deviceId,
    open: () async => signedIn ? db : null,
    now: () => c.now,
  );
}
