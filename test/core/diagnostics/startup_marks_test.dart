import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/startup_marks.dart';

void main() {
  late int ms;
  late StartupMarks marks;

  setUp(() {
    ms = 0;
    marks = StartupMarks(elapsedMs: () => ms);
  });

  void at(int t, String step) {
    ms = t;
    marks.mark(step);
  }

  test('keeps the first moment of each step, in order', () {
    at(0, 'main');
    at(40, 'kv.read');
    at(90, 'kv.read');
    at(120, 'platform');
    expect(marks.marks, {'main': 0, 'kv.read': 40, 'platform': 120});
    expect(marks.describe(), 'main=0 kv.read=40 platform=120');
  });

  test('a wait names the longest step that ended inside it', () {
    at(0, 'main');
    at(400, 'platform');
    at(500, 'library.wait');
    at(900, 'kv.done');
    at(1500, 'table library.');
    at(1600, 'library.shown');
    final slow = marks.slowestSince('library.wait')!;
    expect(slow.step, 'table library.');
    expect(slow.ms, 600);
    expect(marks.since('library.wait', 'library.shown'), 1100);
  });

  test('a step that began before the wait counts only its part inside', () {
    at(0, 'main');
    at(100, 'kv.read');
    at(500, 'library.wait');
    at(1400, 'kv.done');
    at(1500, 'library.shown');
    final slow = marks.slowestSince('library.wait')!;
    expect(slow.step, 'kv.done');
    expect(slow.ms, 900);
  });

  test('nothing to name without the wait mark', () {
    at(0, 'main');
    expect(marks.slowestSince('library.wait'), isNull);
    expect(marks.since('library.wait', 'main'), isNull);
  });

  test('the launch marks run on one clock from first use', () {
    StartupMarks.launch.mark('main');
    expect(StartupMarks.launch.marks['main'], isNonNegative);
  });
}
