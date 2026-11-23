import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/diagnostics/startup_marks.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';
import 'package:kartka/library/state/library_load_probe.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

/// library.load a133bbb8: the first library paint after launch logs where
/// the launch spent its time, and a wait over 1 s names its slowest step.
void main() {
  late int ms;
  late StartupMarks marks;
  late DiagnosticsLog log;
  late LibraryLoadProbe probe;

  setUp(() {
    ms = 0;
    marks = StartupMarks(elapsedMs: () => ms);
    log = DiagnosticsLog(MemoryBlobStore());
    probe = LibraryLoadProbe(marks, ErrorReporter(log));
  });

  void at(int t, String step) {
    ms = t;
    marks.mark(step);
  }

  test(
    'a quick first paint logs the launch marks on the device only',
    () async {
      at(0, 'main');
      at(300, 'library.wait');
      at(800, 'kv.done');
      ms = 900;
      probe.shown();
      final e = (await log.entries()).single;
      expect(e.kind, 'perf.startup');
      expect(e.error, 'main=0 library.wait=300 kv.done=800 library.shown=900');
      expect(isUploadedEntry(e), isFalse);
    },
  );

  test('a first paint 1 s or more after the spinner names the step', () async {
    at(0, 'main');
    at(300, 'library.wait');
    at(500, 'kv.done');
    at(1250, 'table library.');
    ms = 1300;
    probe.shown();
    final probeLine = (await log.entries()).singleWhere(
      (e) => e.kind == 'library.load',
    );
    expect(
      probeLine.error,
      // One text per step, so one board ticket; the times stay in the
      // device's perf.startup line and the perf.slow report.
      'LibraryProbe: library waited on table library.',
    );
    expect(isUploadedEntry(probeLine), isTrue);
  });

  test('only the first paint of the launch reports', () async {
    at(0, 'main');
    at(10, 'library.wait');
    ms = 2000;
    probe
      ..shown()
      ..shown();
    expect(await log.entries(), hasLength(2), reason: 'startup + probe');
  });

  test('no spinner (already loaded) logs the marks, no probe', () async {
    at(0, 'main');
    ms = 5000;
    probe.shown();
    expect((await log.entries()).single.kind, 'perf.startup');
  });
}
