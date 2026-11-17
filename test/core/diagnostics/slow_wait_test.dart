import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

void main() {
  final start = DateTime.utc(2026, 11, 17, 12);
  late DiagnosticsLog log;

  setUp(() => log = DiagnosticsLog(MemoryBlobStore())..route = '/reader/:id');

  // Futures must be born in the fake zone to run on its clock, so each run
  // builds its own log there (the setUp one serves the plain tests).

  /// Runs [body] under a fake clock; returns the entries once logged.
  Future<List<DiagnosticEntry>> run(
    void Function(SlowWaitReporter r, FakeAsync a) body, {
    void Function(DiagnosticsLog log)? prepare,
  }) {
    late List<DiagnosticEntry> out;
    fakeAsync((a) {
      log = DiagnosticsLog(MemoryBlobStore())..route = '/reader/:id';
      prepare?.call(log);
      body(SlowWaitReporter(log, now: () => start.add(a.elapsed)), a);
      a.flushMicrotasks();
      unawaited(log.entries().then((e) => out = e));
      a.flushMicrotasks();
    });
    return Future.value(out);
  }

  test('a wait of 900 ms reports nothing', () async {
    final entries = await run((r, a) {
      final wait = r.begin('reader.open');
      a.elapse(const Duration(milliseconds: 900));
      wait.end();
    });
    expect(entries, isEmpty);
  });

  test('a wait of 1100 ms reports route, operation and duration', () async {
    final entries = await run((r, a) {
      final wait = r.begin('reader.open');
      a.elapse(const Duration(milliseconds: 1100));
      wait.end();
    });
    final e = entries.single;
    expect(e.kind, 'perf.slow');
    expect(e.route, '/reader/:id');
    expect(e.operation, 'reader.open');
    expect(e.durationMs, 1100);
    expect(e.waitId, isNotEmpty);
    expect(e.still, isFalse);
    expect(e.error, 'reader.open waited 1100 ms');
  });

  test('the route is the one on top when the wait began', () async {
    final entries = await run((r, a) {
      final wait = r.begin('library.load');
      log.route = '/browse';
      a.elapse(const Duration(seconds: 2));
      wait.end();
    });
    expect(entries.single.route, '/reader/:id');
  });

  test('two slow waits of one operation differ only in id and ms', () async {
    final entries = await run((r, a) {
      for (final ms in [1200, 3400]) {
        final wait = r.begin('reader.page');
        a.elapse(Duration(milliseconds: ms));
        wait.end();
      }
    });
    expect(entries, hasLength(2));
    expect(
      entries.map((e) => (e.kind, e.route, e.operation)).toSet(),
      hasLength(1),
    );
    expect(entries.map((e) => e.waitId).toSet(), hasLength(2));
    expect(entries.map((e) => e.durationMs), [1200, 3400]);
  });

  test('still waiting at 5 s reports once, the end updates it', () async {
    final entries = await run((r, a) {
      final wait = r.begin('details.load');
      a
        ..elapse(const Duration(seconds: 5))
        ..elapse(const Duration(seconds: 2));
      wait
        ..end()
        ..end(); // idempotent
    });
    expect(entries, hasLength(2));
    final [midway, last] = entries;
    expect(midway.still, isTrue);
    expect(midway.durationMs, 5000);
    expect(last.still, isFalse);
    expect(last.durationMs, 7000);
    expect(last.waitId, midway.waitId);
  });

  test('ending early cancels the 5 s timer', () {
    fakeAsync((a) {
      SlowWaitReporter(log, now: () => start.add(a.elapsed)).begin('x').end();
      expect(a.pendingTimers, isEmpty);
    });
  });

  test('at most maxPerMinute reports a minute', () async {
    final entries = await run((r, a) {
      for (var i = 0; i < SlowWaitReporter.maxPerMinute + 5; i++) {
        final wait = r.begin('library.load');
        a.elapse(const Duration(milliseconds: 1500));
        wait.end();
      }
    });
    expect(entries.length, lessThanOrEqualTo(SlowWaitReporter.maxPerMinute));
    expect(entries, isNotEmpty);
  });

  test('of() shares one reporter per log', () {
    expect(SlowWaitReporter.of(log), same(SlowWaitReporter.of(log)));
  });

  test('entries carry build info the log stamps', () async {
    final entries = await run(
      (r, a) {
        final wait = r.begin('reader.open');
        a.elapse(const Duration(seconds: 2));
        wait.end();
      },
      prepare: (log) => log
        ..build = 412
        ..version = '0.1.0-abc1234',
    );
    expect(entries.single.build, 412);
    expect(entries.single.version, '0.1.0-abc1234');
    final json = entries.single.toJson();
    expect(json['build'], 412);
    expect(json['version'], '0.1.0-abc1234');
    expect(DiagnosticEntry.fromJson(json).operation, 'reader.open');
  });

  test('an entry that names its own build keeps it', () async {
    log.build = 9;
    await log.append(
      DiagnosticEntry(
        at: start,
        kind: 'k',
        error: 'e',
        build: 3,
        version: '0.0.1',
      ),
    );
    expect((await log.entries()).single.build, 3);
  });

  test('old entries without the new fields still decode', () {
    final e = DiagnosticEntry.fromJson({
      'at': '2026-10-29T12:00:00.000Z',
      'kind': 'k',
      'error': 'e',
    });
    expect(
      (e.operation, e.durationMs, e.build, e.still),
      (null, null, null, false),
    );
  });

  test('stampBuild sets what is known and skips 0 and empty', () {
    final bare = DiagnosticsLog(MemoryBlobStore())..stampBuild();
    expect((bare.build, bare.version), (null, null), reason: 'no defines');
    final named = DiagnosticsLog(MemoryBlobStore())
      ..stampBuild(code: 12, name: '0.1.0-abc');
    expect((named.build, named.version), (12, '0.1.0-abc'));
  });
}
