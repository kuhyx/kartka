import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

void main() {
  late DateTime now;
  late DiagnosticsLog log;
  late ErrorReporter reporter;

  setUp(() {
    now = DateTime.utc(2026, 10, 29, 12);
    log = DiagnosticsLog(MemoryBlobStore());
    reporter = ErrorReporter(log, now: () => now);
  });

  Future<List<DiagnosticEntry>> entries() => log.entries();

  test('appends a failure entry with the kind, message and stack', () async {
    reporter.report(
      'ui.snackbar',
      const FormatException('repo URL must be http(s): atsumaru'),
      stack: StackTrace.fromString('#0 a (package:kartka/x.dart:1:2)'),
    );
    final e = (await entries()).single;
    expect(e.kind, 'ui.snackbar');
    expect(e.error, 'FormatException: repo URL must be http(s): atsumaru');
    expect(e.at, now);
    expect(e.stack, ['#0 a (package:kartka/x.dart:1:2)']);
  });

  test('carries the source id when given one', () async {
    reporter.report('browse.page', 'x', sourceId: 'mangadex');
    expect((await entries()).single.sourceId, 'mangadex');
  });

  test('drops a repeat of the same error inside the window', () async {
    reporter
      ..report('k', 'boom')
      ..report('k', 'boom')
      ..report('k', 'other')
      ..report('j', 'boom');
    now = now.add(ErrorReporter.window + const Duration(seconds: 1));
    reporter.report('k', 'boom');
    expect((await entries()).map((e) => '${e.kind}:${e.error}'), [
      'k:boom',
      'k:other',
      'j:boom',
      'k:boom',
    ]);
  });

  test('caps reports per minute so an error loop cannot flood', () async {
    for (var i = 0; i < ErrorReporter.maxPerMinute + 5; i++) {
      reporter.report('k', 'e$i');
    }
    expect(await entries(), hasLength(ErrorReporter.maxPerMinute));
    now = now.add(const Duration(minutes: 1));
    reporter.report('k', 'later');
    expect((await entries()).last.error, 'later');
  });

  test('forgets old repeats so the guard stays small', () async {
    for (var i = 0; i < 3; i++) {
      reporter.report('k', 'e$i');
      now = now.add(const Duration(minutes: 2));
    }
    expect(reporter.tracked, 1);
  });

  test('keeps the innermost frames and the first kartka frames', () async {
    final stack = StackTrace.fromString(
      [
        '#0 inner (dart:core/x.dart:1)',
        '#1 next (package:flutter/a.dart:2)',
        '#2 f (package:flutter/b.dart:3)',
        '#3 g (package:flutter/c.dart:4)',
        '#4 h (package:flutter/d.dart:5)',
        '#5 mine (package:kartka/reader/r.dart:6)',
        '#6 more (package:kartka/app/a.dart:7)',
      ].join('\n'),
    );
    reporter.report('k', 'x', stack: stack);
    expect((await entries()).single.stack, [
      '#0 inner (dart:core/x.dart:1)',
      '#1 next (package:flutter/a.dart:2)',
      '#5 mine (package:kartka/reader/r.dart:6)',
      '#6 more (package:kartka/app/a.dart:7)',
    ]);
  });

  test('never reports from inside its own report', () async {
    late ErrorReporter inner;
    final throwing = _ThrowingError(() => inner.report('k', 'nested'));
    inner = reporter..report('k', throwing);
    final errors = (await entries()).map((e) => e.error);
    expect(errors, isNot(contains('nested')));
  });

  test('of() shares one reporter per log', () {
    expect(ErrorReporter.of(log), same(ErrorReporter.of(log)));
  });
}

/// An error whose `toString` re-enters the reporter, then throws.
class _ThrowingError {
  new(this.onString);

  final void Function() onString;

  @override
  String toString() {
    onString();
    throw StateError('toString failed');
  }
}
