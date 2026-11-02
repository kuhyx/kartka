import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/error_upload.dart';
import 'package:kartka/sync/rtdb_transport.dart';

DiagnosticEntry _entry(
  String error, {
  String kind = 'ui.snackbar',
  int s = 0,
}) => DiagnosticEntry(
  at: DateTime.utc(2026, 10, 29, 12, 0, s),
  kind: kind,
  error: error,
);

void main() {
  late DiagnosticsLog log;
  late MemoryKeyValueStore kv;
  late InMemoryRtdb db;
  late RtdbTransport? transport;
  late int opens;

  ErrorUploader make() => ErrorUploader(
    log: log,
    kv: kv,
    transport: () async {
      opens++;
      return transport;
    },
    deviceId: () async => 'dev.a',
  );

  Map<String, Object?> uploaded() =>
      ((db.tree['errors'] as Map?)?['dev~2Ea'] as Map<String, Object?>?) ?? {};

  setUp(() {
    log = DiagnosticsLog(MemoryBlobStore());
    // A device whose cutoff predates every entry below (see 'cutoff').
    kv = MemoryKeyValueStore({ErrorUploader.sinceKey: '2000-01-01T00:00:00Z'});
    db = InMemoryRtdb();
    transport = db;
    opens = 0;
  });

  test('pushes failure entries once, redacted, skipping perf', () async {
    await log.append(_entry('a https://h.test/x?auth=SECRET by me@x.org'));
    await log.append(_entry('slow frame', kind: 'perf.jank'));
    await log.append(
      DiagnosticEntry(
        at: DateTime.utc(2026),
        kind: 'reader.open',
        error: 'b',
        stack: const ['#0 f (/home/kuhy/src/kartka/lib/x.dart:1)'],
      ),
    );
    final up = make();
    expect(await up.flush(), isTrue);
    final nodes = uploaded();
    expect(nodes, hasLength(2));
    final errors = nodes.values.map((n) => (n! as Map)['error']).toSet();
    expect(errors, {'a https://h.test/x?<redacted> by <email>', 'b'});
    expect('$nodes', isNot(contains('SECRET')));
    expect('$nodes', contains('#0 f (~/src/kartka/lib/x.dart:1)'));
    expect(db.writes, 1);
    expect(await up.flush(), isTrue);
    expect(db.writes, 1, reason: 'already sent');
    expect(await make().flush(), isTrue);
    expect(db.writes, 1, reason: 'the sent set is persisted');
  });

  test('ids are stable and RTDB-safe', () async {
    final a = ErrorUploader.idOf(_entry('x'));
    expect(a, ErrorUploader.idOf(_entry('x')));
    expect(a, isNot(ErrorUploader.idOf(_entry('y'))));
    expect(a, matches(RegExp(r'^[0-9a-f]{20}$')));
  });

  test('batches big backlogs and caps one flush', () async {
    for (var i = 0; i < ErrorUploader.maxPerFlush + 10; i++) {
      await log.append(_entry('e$i', s: i % 60));
    }
    final up = make();
    expect(await up.flush(), isFalse, reason: 'more is left');
    expect(uploaded(), hasLength(ErrorUploader.maxPerFlush));
    expect(db.writes, ErrorUploader.maxPerFlush ~/ ErrorUploader.batch);
    expect(await up.flush(), isTrue);
    expect(uploaded(), hasLength(ErrorUploader.maxPerFlush + 10));
  });

  test('signed out: nothing is sent and nothing is lost', () async {
    await log.append(_entry('a'));
    transport = null;
    final up = make();
    expect(await up.flush(), isFalse);
    transport = db;
    expect(await up.flush(), isTrue);
    expect(uploaded(), hasLength(1));
  });

  test('offline: keeps the entries and retries with backoff', () {
    fakeAsync((async) {
      // Futures must be born in the fake zone to run on its clock.
      log = DiagnosticsLog(MemoryBlobStore());
      kv = MemoryKeyValueStore({
        ErrorUploader.sinceKey: '2000-01-01T00:00:00Z',
      });
      db = InMemoryRtdb();
      transport = db;
      unawaited(log.append(_entry('a')));
      async.flushMicrotasks();
      db.failWith = Exception('offline');
      final up = make()..start();
      unawaited(log.append(_entry('b')));
      async.elapse(ErrorUploader.debounce);
      expect(opens, 1);
      expect(uploaded(), isEmpty);
      async.elapse(ErrorUploader.minBackoff);
      expect(opens, 2);
      db.failWith = null;
      async.elapse(ErrorUploader.minBackoff * 2);
      expect(opens, 3);
      expect(uploaded(), hasLength(2));
      async.elapse(ErrorUploader.maxBackoff);
      expect(opens, 3, reason: 'nothing left, no retry');
      up.dispose();
    });
  });

  test('appends are debounced into one flush; perf does not wake it', () {
    fakeAsync((async) {
      // Futures must be born in the fake zone to run on its clock.
      log = DiagnosticsLog(MemoryBlobStore());
      kv = MemoryKeyValueStore({
        ErrorUploader.sinceKey: '2000-01-01T00:00:00Z',
      });
      db = InMemoryRtdb();
      transport = db;
      final up = make()..start();
      unawaited(log.append(_entry('perf', kind: 'perf.jank')));
      async.elapse(ErrorUploader.debounce * 2);
      expect(opens, 0);
      for (var i = 0; i < 3; i++) {
        unawaited(log.append(_entry('e$i', s: i)));
        async.elapse(const Duration(seconds: 1));
      }
      async.elapse(ErrorUploader.debounce);
      expect(opens, 1);
      expect(uploaded(), hasLength(3));
      up.dispose();
      unawaited(log.append(_entry('after')));
      async.elapse(ErrorUploader.debounce * 2);
      expect(opens, 1, reason: 'disposed');
    });
  });

  test('a flush during a flush runs again after it', () async {
    await log.append(_entry('a'));
    final gate = Completer<void>();
    final up = ErrorUploader(
      log: log,
      kv: kv,
      transport: () async {
        await gate.future;
        return db;
      },
      deviceId: () async => 'dev.a',
    );
    final first = up.flush();
    await log.append(_entry('b', s: 1));
    final second = up.flush();
    gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(uploaded(), hasLength(2));
  });

  test('the sent set stays bounded', () async {
    await kv.set(
      ErrorUploader.sentKey,
      '[${List.generate(ErrorUploader.maxSent, (i) => '"old$i"').join(',')}]',
    );
    await log.append(_entry('new'));
    await make().flush();
    final sent = await kv.get(ErrorUploader.sentKey);
    expect(sent, isNot(contains('"old0"')));
    expect(sent, contains(ErrorUploader.idOf(_entry('new'))));
    await kv.set(ErrorUploader.sentKey, 'not json');
    expect(await make().flush(), isTrue);
  });

  group('cutoff', () {
    ErrorUploader at(DateTime now) => ErrorUploader(
      log: log,
      kv: kv,
      transport: () async => db,
      deviceId: () async => 'dev.a',
      now: () => now,
    );

    setUp(() => kv = MemoryKeyValueStore());

    test('a first run uploads nothing logged before it', () async {
      await log.append(_entry('old backlog'));
      await log.append(_entry('just before', s: 9));
      final up = at(DateTime.utc(2026, 10, 29, 12, 0, 10))..start();
      addTearDown(up.dispose);
      expect(await up.flush(), isTrue);
      expect(uploaded(), isEmpty);
      expect(db.writes, 0);
      expect(await kv.get(ErrorUploader.sinceKey), '2026-10-29T12:00:10.000Z');
      await log.append(_entry('at the cutoff', s: 10));
      await log.append(_entry('after', s: 30));
      expect(await up.flush(), isTrue);
      final errors = uploaded().values.map((n) => (n! as Map)['error']);
      expect(errors.toSet(), {'at the cutoff', 'after'});
    });

    test('the cutoff is kept once set; a restart does not move it', () async {
      await at(DateTime.utc(2026, 10, 29, 12)).flush();
      await log.append(_entry('between launches', s: 5));
      final later = at(DateTime.utc(2026, 10, 30))..start();
      addTearDown(later.dispose);
      expect(await later.flush(), isTrue);
      expect(uploaded(), hasLength(1));
      expect(await kv.get(ErrorUploader.sinceKey), '2026-10-29T12:00:00.000Z');
    });

    test('it is captured at start, not at the delayed first flush', () async {
      var now = DateTime.utc(2026, 10, 29, 12);
      final up = ErrorUploader(
        log: log,
        kv: kv,
        transport: () async => db,
        deviceId: () async => 'dev.a',
        now: () => now,
      )..start();
      addTearDown(up.dispose);
      await log.append(_entry('during the start delay', s: 3));
      now = DateTime.utc(2026, 10, 29, 12, 0, 20);
      expect(await up.flush(), isTrue);
      expect(uploaded(), hasLength(1));
    });
  });
}
