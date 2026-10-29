import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/error_upload.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uploads once sync starts, as the runtime device', () async {
    final log = DiagnosticsLog(MemoryBlobStore());
    await log.append(
      DiagnosticEntry(at: DateTime.utc(2026), kind: 'k', error: 'early'),
    );
    final db = InMemoryRtdb();
    final runtime = SyncRuntime(
      kv: MemoryKeyValueStore(),
      openTransport: () async => db,
      deviceId: () async => 'dev-b',
      startScheduler: false,
    );
    final up = startErrorUploads(
      runtime,
      log: log,
      // An install whose cutoff predates the earlier launch's entry.
      kv: MemoryKeyValueStore({ErrorUploader.sinceKey: '2000-01-01T00:00Z'}),
      startDelay: Duration.zero,
    );
    addTearDown(up.dispose);
    await pumpEventQueue();
    expect(db.tree['errors'], isNull, reason: 'sync has not started');
    await runtime.engine;
    await pumpEventQueue(times: 50);
    expect((db.tree['errors']! as Map)['dev-b'], hasLength(1));
    expect(await runtime.deviceId(), 'dev-b');
  });
}
