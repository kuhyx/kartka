import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/app_errors.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/error_sink.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'writes the shared upload under /kartka/errors; null signed out',
    () async {
      expect(errorSink(null), isNull);
      final db = InMemoryRtdb();
      await errorSink(db)!('kartka/errors', {
        'dev/abc': {'kind': 'x'},
      });
      expect(db.tree['errors'], {
        'dev': {
          'abc': {'kind': 'x'},
        },
      });
    },
  );

  test('the upload rides the runtime transport as its device', () async {
    final db = InMemoryRtdb();
    final runtime = SyncRuntime(
      kv: MemoryKeyValueStore(),
      openTransport: () async => db,
      deviceId: () async => 'dev-1',
      startScheduler: false,
    );
    expect(connectErrorUploads(null, runtime), isNull);
    Future<bool> notAgent() async => false;
    SharedPreferences.setMockInitialValues({});
    final errors = AppErrors.forTest(
      kartkaErrorsConfig(build: 9),
      await ErrorQueue.open(await SharedPreferences.getInstance()),
    );
    final up = connectErrorUploads(errors, runtime, isAgent: notAgent)!;
    addTearDown(up.dispose);
    errors.reporter.report('ui.snackbar', 'Refresh failed: boom');
    expect(await up.flush(), isTrue);
    final sent = (db.tree['errors']! as Map)['dev-1']! as Map;
    expect((sent.values.single! as Map)['build'], 9);
  });

  test('the agent instance uploads nothing', () async {
    final db = InMemoryRtdb();
    final runtime = SyncRuntime(
      kv: MemoryKeyValueStore(),
      openTransport: () async => db,
      deviceId: () async => 'agent',
      startScheduler: false,
    );
    SharedPreferences.setMockInitialValues({});
    final errors = AppErrors.forTest(
      kartkaErrorsConfig(build: 9),
      await ErrorQueue.open(await SharedPreferences.getInstance()),
    );
    Future<bool> agent() async => true;
    final up = connectErrorUploads(errors, runtime, isAgent: agent)!;
    addTearDown(up.dispose);
    errors.reporter.report('ui.snackbar', 'Refresh failed: boom');
    expect(await up.flush(), isFalse, reason: 'no sink: kept queued');
    expect(db.tree['errors'], isNull);
    expect(errors.queue.entries, hasLength(1));
  });
}
