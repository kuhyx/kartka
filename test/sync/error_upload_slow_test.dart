import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/error_upload.dart';
import 'package:kartka/sync/rtdb_transport.dart';

DiagnosticEntry _entry(String kind, {int s = 0}) => DiagnosticEntry(
  at: DateTime.utc(2026, 10, 29, 12, 0, s),
  kind: kind,
  error: 'reader.open waited 1500 ms',
  route: '/reader/:id',
  operation: 'reader.open',
  durationMs: 1500,
  waitId: 'w1',
);

void main() {
  late DiagnosticsLog log;
  late InMemoryRtdb db;
  late int opens;

  ErrorUploader make() => ErrorUploader(
    log: log,
    kv: MemoryKeyValueStore({ErrorUploader.sinceKey: '2000-01-01T00:00:00Z'}),
    transport: () async {
      opens++;
      return db;
    },
    deviceId: () async => 'dev.a',
  );

  setUp(() {
    log = DiagnosticsLog(MemoryBlobStore());
    db = InMemoryRtdb();
    opens = 0;
  });

  test('perf.slow is uploaded with its fields; perf.jank is not', () async {
    log.build = 77;
    await log.append(_entry('perf.jank'));
    await log.append(_entry('perf.slow', s: 1));
    expect(await make().flush(), isTrue);
    final nodes = (db.tree['errors']! as Map)['dev~2Ea']! as Map;
    final node = nodes.values.single! as Map;
    expect(node['kind'], 'perf.slow');
    expect(node['operation'], 'reader.open');
    expect(node['durationMs'], 1500);
    expect(node['waitId'], 'w1');
    expect(node['build'], 77);
  });

  test('a perf.slow append wakes the uploader, perf.jank does not', () {
    fakeAsync((async) {
      // Futures must be born in the fake zone to run on its clock.
      log = DiagnosticsLog(MemoryBlobStore());
      db = InMemoryRtdb();
      final up = make()..start();
      unawaited(log.append(_entry('perf.jank')));
      async.elapse(ErrorUploader.debounce * 2);
      expect(opens, 0);
      unawaited(log.append(_entry('perf.slow', s: 1)));
      async.elapse(ErrorUploader.debounce * 2);
      expect(opens, 1);
      up.dispose();
    });
  });
}
