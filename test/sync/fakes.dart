import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_shadow.dart';

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
  KeyValueStore? kv,
  bool signedIn = true,
  Duration deferFor = const Duration(seconds: 3),
}) async {
  final c = clock ?? TestClock();
  return SyncEngine(
    shadow: await SyncShadow.load(kv ?? MemoryKeyValueStore()),
    deviceId: deviceId,
    open: () async => signedIn ? db : null,
    now: () => c.now,
    deferFor: deferFor,
  );
}
